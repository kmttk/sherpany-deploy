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

variable "acr_username" {
  description = "The username for the Azure Container Registry"
  type        = string
  sensitive   = true
}

variable "acr_password" {
  description = "The password for the Azure Container Registry"
  type        = string
  sensitive   = true
}