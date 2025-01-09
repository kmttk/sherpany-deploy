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
  type        = string
  sensitive   = true
}

variable "acr_password" {
  type        = string
  sensitive   = true
}

variable "github_token" {
  type        = string
  sensitive   = true
}

variable "github_owner" {
  type = string
}