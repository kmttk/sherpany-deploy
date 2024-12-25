variable "azure_subscription_id" {
  type        = string
  sensitive   = true
}

variable "azure_client_id" {
  type        = string
  sensitive   = true
}

variable "azure_client_secret" {
  type        = string
  sensitive   = true
}

variable "azure_tenant_id" {
  type        = string
  sensitive   = true
}

variable "azure_linux_vm_secret" {
  type      = string
  sensitive = true
}
