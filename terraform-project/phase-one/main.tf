# Azure Resource Group
data "azurerm_resource_group" "vm_rg" {
  name = "sherpany-vm-rg"
}

data "azurerm_public_ip" "vm_pip" {
  name                = "ubuntu-pip"
  resource_group_name = data.azurerm_resource_group.vm_rg.name
}

resource "azurerm_resource_group" "sherpany_resources" {
  name     = "sherpany-resources"
  location = "West Europe"
  tags = {
    environment = "production"
    project     = "sherpany"
    owner       = "devops"
  }
}

# Storage Account for Terraform State
resource "azurerm_storage_account" "terraform_state_storage" {
  name                     = "sherpanyterraformstate"
  resource_group_name      = azurerm_resource_group.sherpany_resources.name
  location                 = azurerm_resource_group.sherpany_resources.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version         = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }
  depends_on = [azurerm_resource_group.sherpany_resources]
}

# Storage Container for Terraform State
resource "azurerm_storage_container" "terraform_state_container" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.terraform_state_storage.name
  container_access_type = "private"
  depends_on           = [azurerm_storage_account.terraform_state_storage]
}

# Container Registry
resource "azurerm_container_registry" "sherpany_acr" {
  name                = "sherpanyacr"
  resource_group_name = azurerm_resource_group.sherpany_resources.name
  location            = azurerm_resource_group.sherpany_resources.location
  sku                = "Basic"
  admin_enabled      = true
  depends_on         = [azurerm_resource_group.sherpany_resources]
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
  depends_on = [azurerm_container_registry.sherpany_acr]
}

resource "github_actions_secret" "acr_username" {
  repository      = var.github_repository
  secret_name     = "ACR_USERNAME"
  plaintext_value = data.azurerm_container_registry.sherpany_acr.admin_username
  depends_on = [ provider.github ]
}

resource "github_actions_secret" "acr_password" {
  repository      = var.github_repository
  secret_name     = "ACR_PASSWORD"
  plaintext_value = data.azurerm_container_registry.sherpany_acr.admin_password
  depends_on = [ provider.github ]
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "aks-law" {
  name                = "sherpany-law"
  location            = azurerm_resource_group.sherpany_resources.location
  resource_group_name = azurerm_resource_group.sherpany_resources.name
  sku                = "PerGB2018"
  retention_in_days   = 30

  tags = {
    environment = "production"
    project     = "sherpany"
    owner       = "devops"
  }
  depends_on = [azurerm_resource_group.sherpany_resources]
}

# Get the storage account key
data "azurerm_storage_account" "terraform_state_storage" {
  name                = azurerm_storage_account.terraform_state_storage.name
  resource_group_name = azurerm_resource_group.sherpany_resources.name
  depends_on          = [azurerm_storage_account.terraform_state_storage]
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "sherpany_aks" {
  name                = "sherpany-aks"
  location            = azurerm_resource_group.sherpany_resources.location
  resource_group_name = azurerm_resource_group.sherpany_resources.name
  dns_prefix          = "sherpanyaks"
  
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks-law.id
  }

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "production"
    project     = "sherpany"
    owner       = "devops"
  }

  depends_on = [azurerm_resource_group.sherpany_resources, azurerm_log_analytics_workspace.aks-law]
}