# ==================== WINDOWS VIRTUAL MACHINES ====================

resource "azurerm_windows_virtual_machine" "app1" {
  name                = "vm-app1-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B1s"

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.app1.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-smalldisk-g2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Application = "App1"
    Port        = "8080"
  }
}

resource "azurerm_windows_virtual_machine" "app2" {
  name                = "vm-app2-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_B1s"

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [
    azurerm_network_interface.app2.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-smalldisk-g2"
    version   = "latest"
  }

  tags = {
    Environment = var.environment
    Application = "App2"
    Port        = "8081"
  }
}

# ==================== CUSTOM SCRIPT EXTENSION - APP1 ====================

resource "azurerm_virtual_machine_extension" "app1_iis" {
  name               = "iis-config-app1"
  virtual_machine_id = azurerm_windows_virtual_machine.app1.id
  publisher          = "Microsoft.Compute"
  type               = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    "commandToExecute" = "powershell -Command \"Install-WindowsFeature -name Web-Server -IncludeManagementTools; $content = '<html><body><h1>App1 Running on Port 8080</h1></body></html>'; Set-Content -Path 'C:\\\\inetpub\\\\wwwroot\\\\index.html' -Value $content; Get-Service W3SVC | Start-Service\""
  })

  depends_on = [azurerm_windows_virtual_machine.app1]
}

# ==================== CUSTOM SCRIPT EXTENSION - APP2 ====================

resource "azurerm_virtual_machine_extension" "app2_iis" {
  name               = "iis-config-app2"
  virtual_machine_id = azurerm_windows_virtual_machine.app2.id
  publisher          = "Microsoft.Compute"
  type               = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    "commandToExecute" = "powershell -Command \"Install-WindowsFeature -name Web-Server -IncludeManagementTools; $content = '<html><body><h1>App2 Running on Port 8081</h1></body></html>'; Set-Content -Path 'C:\\\\inetpub\\\\wwwroot\\\\index.html' -Value $content; Get-Service W3SVC | Start-Service\""
  })

  depends_on = [azurerm_windows_virtual_machine.app2]
}

# ==================== OUTPUTS ====================

output "app1_vm_id" {
  value       = azurerm_windows_virtual_machine.app1.id
  description = "App1 VM ID"
}

output "app2_vm_id" {
  value       = azurerm_windows_virtual_machine.app2.id
  description = "App2 VM ID"
}

output "app1_vm_name" {
  value       = azurerm_windows_virtual_machine.app1.name
  description = "App1 VM Name"
}

output "app2_vm_name" {
  value       = azurerm_windows_virtual_machine.app2.name
  description = "App2 VM Name"
}
