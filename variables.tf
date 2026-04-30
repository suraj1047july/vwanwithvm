variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure Region for resources"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (prod, dev, staging)"
  type        = string
  default     = "prod"
}

variable "vm_username" {
  description = "VM Administrator username"
  type        = string
  default     = "azureuser"
}

variable "vm_password" {
  description = "VM Administrator password (min 12 chars, uppercase, lowercase, numbers, special chars)"
  type        = string
  sensitive   = true
}

variable "appgw_capacity" {
  description = "Application Gateway capacity"
  type        = number
  default     = 2
}

variable "firewall_sku" {
  description = "Firewall SKU (Standard or Premium)"
  type        = string
  default     = "Standard"
  
  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku)
    error_message = "Firewall SKU must be either Standard or Premium."
  }
}
