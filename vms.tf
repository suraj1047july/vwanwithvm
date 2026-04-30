# ==================== VIRTUAL MACHINES ====================

# Windows image data source (you can change to Ubuntu if preferred)
data "azurerm_client_config" "current" {}

# VM 1 for App 1
resource "azurerm_windows_virtual_machine" "vm_app1" {
  name                = "vm-app1-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  size = "Standard_B2s"
  admin_username      = var.vm_username
  admin_password      = var.vm_password

  network_interface_ids = [
    azurerm_network_interface.nic_app1.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Application = "App1"
    Port        = "8080"
  }
}

# Custom Script Extension for VM1 (Install IIS and App)
resource "azurerm_virtual_machine_extension" "vm1_extension" {
  name                       = "ConfigureApp1"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm_app1.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    "commandToExecute" = "powershell -Command \"Install-WindowsFeature -name Web-Server -IncludeManagementTools; Add-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value '<h1>App1 Running on Port 8080</h1>'\""
  })
}

# VM 2 for App 2
resource "azurerm_windows_virtual_machine" "vm_app2" {
  name                = "vm-app2-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.vwan_rg.name
  size = "Standard_B2s"
  admin_username      = var.vm_username
  admin_password      = var.vm_password

  network_interface_ids = [
    azurerm_network_interface.nic_app2.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Application = "App2"
    Port        = "8081"
  }
}

# Custom Script Extension for VM2
resource "azurerm_virtual_machine_extension" "vm2_extension" {
  name                       = "ConfigureApp2"
  virtual_machine_id         = azurerm_windows_virtual_machine.vm_app2.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    "commandToExecute" = "powershell -Command \"Install-WindowsFeature -name Web-Server -IncludeManagementTools; Add-Content -Path 'C:\\inetpub\\wwwroot\\index.html' -Value '<h1>App2 Running on Port 8081</h1>'\""
  })
}

# ==================== UPDATE APP GATEWAY BACKEND POOLS ====================

# This resource updates the App Gateway with actual VM IPs
#resource "azurerm_application_gateway_backend_address_pool_address" "pool_app1" {
 # backend_address_pool_id = "${azurerm_application_gateway.app_gateway.id}/backendAddressPools/backend-app1"
#  ip_address              = azurerm_network_interface.nic_app1.private_ip_address
#  fqdn                    = null
#
#  depends_on = [azurerm_application_gateway.app_gateway]
#}

#resource "azurerm_application_gateway_backend_address_pool_address" "pool_app2" {
#  backend_address_pool_id = "${azurerm_application_gateway.app_gateway.id}/backendAddressPools/backend-app2"
#  ip_address              = azurerm_network_interface.nic_app2.private_ip_address
#  fqdn                    = null

#  depends_on = [azurerm_application_gateway.app_gateway]
#}
