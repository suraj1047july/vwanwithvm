terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  cloud {
    organization = "terraform_learn_all_cloud"
    workspaces {
      name = "Disconnected-Env"
    }
  }
}

provider "azurerm" {
  features {}
}

# ================= VARIABLES =================

variable "resource_group_name" {
  default = "rg-vwan-prod"
}

variable "location" {
  default = "eastus"
}

variable "environment" {
  default = "prod"
}

variable "admin_username" {
  description = "VM admin username"
  default = "azureuser"
  type        = string
}

variable "admin_password" {
  description = "VM admin password"
  type        = string
  default = "Admin@123456789"
  sensitive   = true
}

# ================= RESOURCE GROUP =================

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# ================= VWAN =================

resource "azurerm_virtual_wan" "main" {
  name                = "vwan-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  type                = "Standard"
}

resource "azurerm_virtual_hub" "main" {
  name                = "vhub-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  virtual_wan_id      = azurerm_virtual_wan.main.id
  address_prefix      = "192.168.0.0/23"
}

# ================= VNets =================

resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet-app1"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet1" {
  name                 = "subnet-app1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_virtual_network" "vnet2" {
  name                = "vnet-app2"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.1.0.0/16"]
}

resource "azurerm_subnet" "subnet2" {
  name                 = "subnet-app2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.1.1.0/24"]
}

# ================= HUB CONNECTIONS =================

resource "azurerm_virtual_hub_connection" "vnet1" {
  name                      = "conn-vnet1"
  virtual_hub_id            = azurerm_virtual_hub.main.id
  remote_virtual_network_id = azurerm_virtual_network.vnet1.id
}

resource "azurerm_virtual_hub_connection" "vnet2" {
  name                      = "conn-vnet2"
  virtual_hub_id            = azurerm_virtual_hub.main.id
  remote_virtual_network_id = azurerm_virtual_network.vnet2.id
}

# ================= FIREWALL POLICY =================

resource "azurerm_firewall_policy" "main" {
  name                = "fw-policy"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"
}

# ================= AZURE FIREWALL (FIXED) =================

resource "azurerm_firewall" "main" {
  name                = "fw-hub"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  sku_name = "AZFW_Hub"
  sku_tier = "Standard"

  firewall_policy_id = azurerm_firewall_policy.main.id

  virtual_hub {
    virtual_hub_id  = azurerm_virtual_hub.main.id
    public_ip_count = 1
  }
}

# ================= NICs =================

resource "azurerm_network_interface" "app1" {
  name                = "nic-app1"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
  }
}

resource "azurerm_network_interface" "app2" {
  name                = "nic-app2"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.10"
  }
}

# ================= APP GW VNET =================

resource "azurerm_virtual_network" "appgw" {
  name                = "vnet-appgw"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["172.16.0.0/24"]
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.appgw.name
  address_prefixes     = ["172.16.0.0/26"]
}

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ================= APPLICATION GATEWAY (FIXED) =================

resource "azurerm_application_gateway" "main" {
  name                = "appgw"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "gwconfig"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "app1"
    ip_addresses = [
      azurerm_network_interface.app1.private_ip_address
    ]
  }

  backend_address_pool {
    name = "app2"
    ip_addresses = [
      azurerm_network_interface.app2.private_ip_address
    ]
  }

  backend_http_settings {
    name     = "app1-setting"
    port     = 8080
    protocol = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 20
  }

  backend_http_settings {
    name     = "app2-setting"
    port     = 8081
    protocol = "Http"
    cookie_based_affinity = "Disabled"
    request_timeout       = 20
  }

  http_listener {
    name                           = "listener"
    frontend_ip_configuration_name = "frontend"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "rule1"
    rule_type                  = "Basic"
    http_listener_name         = "listener"
    backend_address_pool_name  = "app1"
    backend_http_settings_name = "app1-setting"
    priority                   = 1
  }
}
