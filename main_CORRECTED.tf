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
      name ="Disconnected-Env"
    }
}
}

provider "azurerm" {
  features {}
}

# ==================== VARIABLES ====================

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "resource_group_name" {
  type        = string
  default     = "rg-vwan-prod"
  description = "Resource Group Name"
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "Azure Region"
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment name"
}

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "VM Admin Username"
}

variable "admin_password" {
  type        = string
  sensitive   = true
  description = "VM Admin Password (min 12 chars, must include uppercase, lowercase, numbers, special chars)"
}

# ==================== RESOURCE GROUP ====================

resource "azurerm_resource_group" "main" {
  name       = var.resource_group_name
  location   = var.location

  tags = {
    Environment = var.environment
    CreatedBy   = "Terraform"
  }
}

# ==================== VIRTUAL WAN ====================

resource "azurerm_virtual_wan" "main" {
  name                = "vwan-${var.environment}-${var.location}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  type                = "Standard"

  tags = {
    Environment = var.environment
  }
}

# ==================== VIRTUAL HUB ====================

resource "azurerm_virtual_hub" "main" {
  name                = "vhub-${var.environment}-${var.location}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  virtual_wan_id      = azurerm_virtual_wan.main.id
  address_prefix      = "192.168.0.0/23"

  tags = {
    Environment = var.environment
  }
}

# ==================== VNETS ====================

# VNET 1 - App1
resource "azurerm_virtual_network" "vnet1" {
  name                = "vnet-app1-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_subnet" "vnet1_app" {
  name                 = "subnet-app1"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet1.name
  address_prefixes     = ["10.0.1.0/24"]
}

# VNET 2 - App2
resource "azurerm_virtual_network" "vnet2" {
  name                = "vnet-app2-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.1.0.0/16"]

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_subnet" "vnet2_app" {
  name                 = "subnet-app2"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.vnet2.name
  address_prefixes     = ["10.1.1.0/24"]
}

# ==================== VWAN HUB CONNECTIONS ====================

resource "azurerm_virtual_hub_connection" "vnet1" {
  name                      = "conn-vnet1-to-hub"
  virtual_hub_id            = azurerm_virtual_hub.main.id
  remote_virtual_network_id = azurerm_virtual_network.vnet1.id

  depends_on = [azurerm_virtual_hub.main]
}

resource "azurerm_virtual_hub_connection" "vnet2" {
  name                      = "conn-vnet2-to-hub"
  virtual_hub_id            = azurerm_virtual_hub.main.id
  remote_virtual_network_id = azurerm_virtual_network.vnet2.id

  depends_on = [azurerm_virtual_hub.main]
}

# ==================== AZURE FIREWALL ====================

resource "azurerm_public_ip" "firewall" {
  name                = "pip-firewall-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_firewall" "main" {
  name                = "fw-${var.environment}-${var.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "AZFW_VHub"
  sku_tier            = "Standard"
  virtual_hub_id      = azurerm_virtual_hub.main.id

  tags = {
    Environment = var.environment
  }

  depends_on = [azurerm_public_ip.firewall]
}

# ==================== FIREWALL POLICY ====================

resource "azurerm_firewall_policy" "main" {
  name                = "fwpol-${var.environment}-${var.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  tags = {
    Environment = var.environment
  }
}

# ==================== FIREWALL POLICY - RULE COLLECTIONS ====================

resource "azurerm_firewall_policy_rule_collection_group" "main" {
  name               = "fwpol-rcg-${var.environment}"
  firewall_policy_id = azurerm_firewall_policy.main.id
  priority           = 100

  # ==================== APPLICATION RULES ====================
  application_rule_collection {
    name     = "app-rules-collection"
    priority = 100
    action   = "Allow"

    rule {
      name             = "allow-google-microsoft"
      source_addresses = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_fqdns = [
        "google.com",
        "*.google.com",
        "*.microsoft.com",
        "microsoft.com"
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "allow-dns"
      source_addresses = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_fqdns = ["*"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  # ==================== NETWORK RULES ====================
  network_rule_collection {
    name     = "network-rules-collection"
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
      name                  = "allow-dns-udp"
      source_addresses      = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_addresses = ["*"]
      protocols             = ["UDP"]
      destination_ports     = ["53"]
    }

    rule {
      name                  = "allow-outbound-https"
      source_addresses      = ["10.0.0.0/16", "10.1.0.0/16"]
      destination_addresses = ["*"]
      protocols             = ["TCP"]
      destination_ports     = ["443"]
    }
  }
}

# ==================== APPLICATION GATEWAY VNET & SUBNET ====================

resource "azurerm_virtual_network" "appgw_vnet" {
  name                = "vnet-appgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["192.168.0.0/24"]

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.appgw_vnet.name
  address_prefixes     = ["192.168.0.0/26"]
}

# ==================== NETWORK SECURITY GROUPS ====================

resource "azurerm_network_security_group" "app1" {
  name                = "nsg-app1-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-http-8080"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vnet"
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

resource "azurerm_network_security_group" "app2" {
  name                = "nsg-app2-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "allow-http-8081"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8081"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-vnet"
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

# ==================== ASSOCIATE NSG TO SUBNETS ====================

resource "azurerm_subnet_network_security_group_association" "app1" {
  subnet_id                 = azurerm_subnet.vnet1_app.id
  network_security_group_id = azurerm_network_security_group.app1.id
}

resource "azurerm_subnet_network_security_group_association" "app2" {
  subnet_id                 = azurerm_subnet.vnet2_app.id
  network_security_group_id = azurerm_network_security_group.app2.id
}

# ==================== NETWORK INTERFACES ====================

resource "azurerm_network_interface" "app1" {
  name                = "nic-app1-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vnet1_app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
  }

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_network_interface" "app2" {
  name                = "nic-app2-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vnet2_app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.10"
  }

  tags = {
    Environment = var.environment
  }
}

# ==================== ROUTE TABLES ====================

resource "azurerm_route_table" "app1" {
  name                = "rt-app1-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  disable_bgp_route_propagation = false

  route {
    name           = "default-to-fw"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualNetworkGateway"
  }

  route {
    name           = "to-vnet2"
    address_prefix = "10.1.0.0/16"
    next_hop_type  = "VirtualNetworkGateway"
  }

  tags = {
    Environment = var.environment
  }
}

resource "azurerm_route_table" "app2" {
  name                = "rt-app2-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  disable_bgp_route_propagation = false

  route {
    name           = "default-to-fw"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualNetworkGateway"
  }

  route {
    name           = "to-vnet1"
    address_prefix = "10.0.0.0/16"
    next_hop_type  = "VirtualNetworkGateway"
  }

  tags = {
    Environment = var.environment
  }
}

# ==================== ASSOCIATE ROUTE TABLES ====================

resource "azurerm_subnet_route_table_association" "app1" {
  subnet_id      = azurerm_subnet.vnet1_app.id
  route_table_id = azurerm_route_table.app1.id
}

resource "azurerm_subnet_route_table_association" "app2" {
  subnet_id      = azurerm_subnet.vnet2_app.id
  route_table_id = azurerm_route_table.app2.id
}

# ==================== PUBLIC IP FOR APP GATEWAY ====================

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = {
    Environment = var.environment
  }
}

# ==================== APPLICATION GATEWAY ====================

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}-${var.location}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_ip_configuration {
    name                 = "frontend-public-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  backend_address_pool {
    name = "backend-app1"
  }

  backend_address_pool {
    name = "backend-app2"
  }

  backend_http_settings {
    name                  = "http-settings-8080"
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 20
    probe_name            = "probe-8080"
  }

  backend_http_settings {
    name                  = "http-settings-8081"
    cookie_based_affinity = "Disabled"
    port                  = 8081
    protocol              = "Http"
    request_timeout       = 20
    probe_name            = "probe-8081"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-public-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "PathBasedRouting"
    http_listener_name         = "http-listener"
    url_path_map_name          = "path-map"
    priority                   = 1
  }

  url_path_map {
    name                               = "path-map"
    default_backend_address_pool_name  = "backend-app1"
    default_backend_http_settings_name = "http-settings-8080"

    path_rule {
      name                       = "path-rule-app1"
      paths                      = ["/app1/*"]
      backend_address_pool_name  = "backend-app1"
      backend_http_settings_name = "http-settings-8080"
    }

    path_rule {
      name                       = "path-rule-app2"
      paths                      = ["/app2/*"]
      backend_address_pool_name  = "backend-app2"
      backend_http_settings_name = "http-settings-8081"
    }
  }

  probe {
    name                = "probe-8080"
    protocol            = "Http"
    path                = "/"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  probe {
    name                = "probe-8081"
    protocol            = "Http"
    path                = "/"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }

  tags = {
    Environment = var.environment
  }

  depends_on = [
    azurerm_network_interface.app1,
    azurerm_network_interface.app2
  ]
}

# ==================== BACKEND POOL ADDRESSES ====================

resource "azurerm_application_gateway_backend_address_pool_address" "app1" {
  backend_address_pool_id = "${azurerm_application_gateway.main.id}/backendAddressPools/backend-app1"
  ip_address              = azurerm_network_interface.app1.private_ip_address

  depends_on = [azurerm_application_gateway.main]
}

resource "azurerm_application_gateway_backend_address_pool_address" "app2" {
  backend_address_pool_id = "${azurerm_application_gateway.main.id}/backendAddressPools/backend-app2"
  ip_address              = azurerm_network_interface.app2.private_ip_address

  depends_on = [azurerm_application_gateway.main]
}

# ==================== OUTPUTS ====================

output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Resource Group Name"
}

output "app_gateway_public_ip" {
  value       = azurerm_public_ip.appgw.ip_address
  description = "Application Gateway Public IP"
}

output "firewall_public_ip" {
  value       = azurerm_public_ip.firewall.ip_address
  description = "Firewall Public IP"
}

output "app1_private_ip" {
  value       = azurerm_network_interface.app1.private_ip_address
  description = "App1 VM Private IP"
}

output "app2_private_ip" {
  value       = azurerm_network_interface.app2.private_ip_address
  description = "App2 VM Private IP"
}

output "virtual_wan_id" {
  value       = azurerm_virtual_wan.main.id
  description = "Virtual WAN ID"
}

output "virtual_hub_id" {
  value       = azurerm_virtual_hub.main.id
  description = "Virtual Hub ID"
}

output "firewall_id" {
  value       = azurerm_firewall.main.id
  description = "Azure Firewall ID"
}

output "appgw_id" {
  value       = azurerm_application_gateway.main.id
  description = "Application Gateway ID"
}
