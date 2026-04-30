terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
cloud {
    organization = "terraform_learn_all_cloud"
    workspaces {
      name ="Disconnected-Env"
    }
}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Variables
variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "location" {
  description = "Azure Region"
  default     = "eastus"
}

variable "environment" {
  description = "Environment name"
  default     = "prod"
}

# Resource Group
resource "azurerm_resource_group" "vwan_rg" {
  name       = "rg-vwan-${var.environment}"
  location   = var.location
}

# ==================== VIRTUAL WAN ====================

resource "azurerm_virtual_wan" "vwan" {
  name                = "vwan-${var.environment}"
  resource_group_name = azurerm_resource_group.vwan_rg.name
  location            = var.location
  type                = "Standard"

  tags = {
    Environment = var.environment
  }
}

# VWAN Hub
resource "azurerm_virtual_hub" "vwan_hub" {
  name                = "vwan-hub-${var.location}"
  resource_group_name = azurerm_resource_group.vwan_rg.name
  location            = var.location
  virtual_wan_id      = azurerm_virtual_wan.vwan.id
  address_prefix      = "192.168.0.0/23"

  tags = {
    Environment = var.environment
  }
}

# ==================== VNETS ====================

# VNET 1
resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet-app1-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Environment = var.environment
  }
}

# Subnet for App1
resource "azurerm_subnet" "subnet_app1" {
  name                 = "subnet-app1"
  resource_group_name  = azurerm_resource_group.vwan_rg.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Gateway Subnet for VNET1
resource "azurerm_subnet" "gateway_subnet_vnet1" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.vwan_rg.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.0.0.0/27"]
}

# VNET 2
resource "azurerm_virtual_network" "vnet2" {
  name                = "vnet-app2-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  address_space       = ["10.1.0.0/16"]

  tags = {
    Environment = var.environment
  }
}

# Subnet for App2
resource "azurerm_subnet" "subnet_app2" {
  name                 = "subnet-app2"
  resource_group_name  = azurerm_resource_group.vwan_rg.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Gateway Subnet for VNET2
resource "azurerm_subnet" "gateway_subnet_vnet2" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.vwan_rg.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.1.0.0/27"]
}

# ==================== VWAN HUB CONNECTIONS ====================

resource "azurerm_virtual_hub_connection" "vnet1_connection" {
  name                      = "conn-app1-to-hub"
  virtual_hub_id            = azurerm_virtual_hub.vwan_hub.id
  remote_virtual_network_id = azurerm_virtual_network.vnet1.id
  
  depends_on = [
    azurerm_virtual_hub.vwan_hub,
    azurerm_virtual_network.vnet1
  ]
}

resource "azurerm_virtual_hub_connection" "vnet2_connection" {
  name                      = "conn-app2-to-hub"
  virtual_hub_id            = azurerm_virtual_hub.vwan_hub.id
  remote_virtual_network_id = azurerm_virtual_network.vnet2.id
  
  depends_on = [
    azurerm_virtual_hub.vwan_hub,
    azurerm_virtual_network.vnet2
  ]
}

# ==================== FIREWALL ====================

resource "azurerm_public_ip" "firewall_pip" {
  name                = "pip-firewall-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "vwan_firewall" {
  name                = "fw-vwan"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  sku_name            = "AZFW_Hub"
  sku_tier            = "Standard"

  virtual_hub {
    virtual_hub_id  = azurerm_virtual_hub.vwan_hub.id
    public_ip_count = 1
  }
}

  tags = {
    Environment = var.environment
  }
}

# Firewall Policy
resource "azurerm_firewall_policy" "fw_policy" {
  name                = "fwpol-vwan-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  sku                 = "Standard"

  tags = {
    Environment = var.environment
  }
}

# Firewall Policy Rule Collection Group
resource "azurerm_firewall_policy_rule_collection_group" "fw_rules" {
  name               = "fw-rules-collection"
  firewall_policy_id = azurerm_firewall_policy.fw_policy.id
  priority           = 100

  # Application Rules for Outbound Internet
  application_rule_collection {
    name     = "app-rules"
    priority = 100
    action   = "Allow"

    rule {
      name             = "allow-google-microsoft"
      source_addresses = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_fqdns = [
        "google.com",
        "*.microsoft.com",
        "*.googleapis.com"
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  # Network Rules for East-West Traffic
  network_rule_collection {
    name     = "network-rules"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "allow-east-west"
      source_addresses      = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_addresses = ["10.0.0.0/16", "10.1.0.0/16"]
      protocols             = ["TCP", "UDP"]
      destination_ports     = ["*"]
    }

    rule {
      name                  = "allow-outbound-dns"
      source_addresses      = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_addresses = ["*"]
      protocols             = ["UDP"]
      destination_ports     = ["53"]
    }
  }
}

# ==================== APPLICATION GATEWAY ====================

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw_pip" {
  name                = "pip-appgw-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Subnet for Application Gateway (in hub)
resource "azurerm_virtual_network" "hub_vnet" {
  name                = "vnet-hub-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  address_space       = ["192.168.0.0/24"]
}

resource "azurerm_subnet" "appgw_subnet" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.vwan_rg.name
  virtual_network_name = azurerm_virtual_network.hub_vnet.name
  address_prefixes     = ["192.168.0.0/26"]
}

# Application Gateway
resource "azurerm_application_gateway" "app_gateway" {
  name                = "appgw-vwan-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw_subnet.id
  }

  # Frontend
  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-public"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  # HTTP Listener
  http_listener {
    name                           = "listener-http"
    frontend_ip_configuration_name = "frontend-public"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  # Backend Pools (Placeholder - will be updated with VM IPs)
  backend_address_pool {
    name = "backend-app1"
    backend_addresses {
    ip_address = azurerm_network_interface.nic_app1.private_ip_address
  }
  }

  backend_address_pool {
    name = "backend-app2"
     backend_addresses {
    ip_address = azurerm_network_interface.nic_app2.private_ip_address
  }
  }

  # Backend Settings
  backend_http_settings {
    name                  = "http-settings-8080"
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 20
  }

  backend_http_settings {
    name                  = "http-settings-8081"
    cookie_based_affinity = "Disabled"
    port                  = 8081
    protocol              = "Http"
    request_timeout       = 20
  }

  # Routing Rules
  request_routing_rule {
    name               = "rule-app1"
    rule_type          = "PathBasedRouting"
    http_listener_name = "listener-http"
    url_path_map_name  = "url-path-map"
  }

  # URL Path Map
  url_path_map {
    name                               = "url-path-map"
    default_backend_address_pool_name  = "backend-app1"
    default_backend_http_settings_name = "http-settings-8080"

    path_rule {
      name                       = "rule-app1"
      paths                      = ["/app1/*"]
      backend_address_pool_name  = "backend-app1"
      backend_http_settings_name = "http-settings-8080"
    }

    path_rule {
      name                       = "rule-app2"
      paths                      = ["/app2/*"]
      backend_address_pool_name  = "backend-app2"
      backend_http_settings_name = "http-settings-8081"
    }
  }

  depends_on = [
    azurerm_public_ip.appgw_pip
  ]

  tags = {
    Environment = var.environment
  }
}

# ==================== NETWORK SECURITY GROUPS ====================

# NSG for App1
resource "azurerm_network_security_group" "nsg_app1" {
  name                = "nsg-app1-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  security_rule {
    name                       = "allow-app-gateway-8080"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "192.168.0.0/26"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vnet-traffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound-https"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
  }
}

# NSG for App2
resource "azurerm_network_security_group" "nsg_app2" {
  name                = "nsg-app2-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  security_rule {
    name                       = "allow-app-gateway-8081"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8081"
    source_address_prefix      = "192.168.0.0/26"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vnet-traffic"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-outbound-https"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    Environment = var.environment
  }
}

# Associate NSGs to Subnets
resource "azurerm_subnet_network_security_group_association" "app1_nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet_app1.id
  network_security_group_id = azurerm_network_security_group.nsg_app1.id
}

resource "azurerm_subnet_network_security_group_association" "app2_nsg_assoc" {
  subnet_id                 = azurerm_subnet.subnet_app2.id
  network_security_group_id = azurerm_network_security_group.nsg_app2.id
}

# ==================== ROUTE TABLES ====================

# Route Table for App1
resource "azurerm_route_table" "rt_app1" {
  name                = "rt-app1-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  route {
    name                   = "to-vnet2-via-fw"
    address_prefix         = "10.1.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "192.168.0.4"  # Firewall IP in hub (example)
  }

  route {
    name           = "default-via-fw"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "192.168.0.4"
  }

  tags = {
    Environment = var.environment
  }
}

# Route Table for App2
resource "azurerm_route_table" "rt_app2" {
  name                = "rt-app2-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  route {
    name                   = "to-vnet1-via-fw"
    address_prefix         = "10.0.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = "192.168.0.4"
  }

  route {
    name           = "default-via-fw"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "192.168.0.4"
  }

  tags = {
    Environment = var.environment
  }
}

# Associate Route Tables
resource "azurerm_subnet_route_table_association" "app1_rt_assoc" {
  subnet_id      = azurerm_subnet.subnet_app1.id
  route_table_id = azurerm_route_table.rt_app1.id
}

resource "azurerm_subnet_route_table_association" "app2_rt_assoc" {
  subnet_id      = azurerm_subnet.subnet_app2.id
  route_table_id = azurerm_route_table.rt_app2.id
}

# ==================== NETWORK INTERFACES ====================

resource "azurerm_network_interface" "nic_app1" {
  name                = "nic-vm-app1-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.subnet_app1.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
  }
}

resource "azurerm_network_interface" "nic_app2" {
  name                = "nic-vm-app2-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.subnet_app2.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.10"
  }
}

# ==================== OUTPUTS ====================

output "vwan_hub_id" {
  value = azurerm_virtual_hub.vwan_hub.id
}

output "app_gateway_public_ip" {
  value = azurerm_public_ip.appgw_pip.ip_address
}

output "firewall_public_ip" {
  value = azurerm_public_ip.firewall_pip.ip_address
}

output "vm1_nic_private_ip" {
  value = azurerm_network_interface.nic_app1.private_ip_address
}

output "vm2_nic_private_ip" {
  value = azurerm_network_interface.nic_app2.private_ip_address
}
