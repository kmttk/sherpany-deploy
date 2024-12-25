# Azure Resource Group
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
  admin_enabled      = false
  depends_on         = [azurerm_resource_group.sherpany_resources]
}

# Azure Database for PostgreSQL
resource "azurerm_postgresql_server" "postgres" {
  name                = "sherpany-psql"
  location            = azurerm_resource_group.sherpany_resources.location
  resource_group_name = azurerm_resource_group.sherpany_resources.name

  administrator_login          = "psqladmin"
  administrator_login_password = "H@Sh1CoR3!"  # Change this in production

  sku_name   = "GP_Gen5_2"
  version    = "11"
  storage_mb = 5120

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled           = true
  public_network_access_enabled = true  # Disable in production

  ssl_enforcement_enabled = true
  depends_on = [azurerm_resource_group.sherpany_resources]
}

# PostgreSQL Database
resource "azurerm_postgresql_database" "db" {
  name                = "testdb"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
  server_name         = data.azurerm_postgresql_server.postgres.name
  charset             = "UTF8"
  collation           = "English_United States.1252"

  depends_on = [azurerm_postgresql_server.postgres]
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