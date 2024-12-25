# Azure Resource Group
resource "azurerm_resource_group" "sherpany_rg" {
  name     = "sherpany-rg"
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
  resource_group_name      = azurerm_resource_group.sherpany_rg.name
  location                 = azurerm_resource_group.sherpany_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version         = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }
  depends_on = [azurerm_resource_group.sherpany_rg]
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
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  location            = azurerm_resource_group.sherpany_rg.location
  sku                = "Basic"
  admin_enabled      = false
  depends_on         = [azurerm_resource_group.sherpany_rg]
}

# Azure Database for PostgreSQL
resource "azurerm_postgresql_server" "postgres" {
  name                = "sherpany-psql"
  location            = azurerm_resource_group.sherpany_rg.location
  resource_group_name = azurerm_resource_group.sherpany_rg.name

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
  depends_on = [azurerm_resource_group.sherpany_rg]
}

# PostgreSQL Database
resource "azurerm_postgresql_database" "db" {
  name                = "testdb"
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  server_name         = azurerm_postgresql_server.postgres.name
  charset             = "UTF8"
  collation          = "English_United States.1252"
  depends_on         = [azurerm_postgresql_server.postgres]
}

# PostgreSQL Firewall Rule for AKS
resource "azurerm_postgresql_firewall_rule" "aks" {
  name                = "aks-nodes"
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  server_name         = azurerm_postgresql_server.postgres.name
  start_ip_address    = azurerm_kubernetes_cluster.sherpany_aks.network_profile[0].service_cidr
  end_ip_address      = azurerm_kubernetes_cluster.sherpany_aks.network_profile[0].service_cidr
  depends_on          = [azurerm_postgresql_server.postgres, azurerm_kubernetes_cluster.sherpany_aks]
}

# Initialize Database Schema
resource "null_resource" "db_setup" {
  provisioner "local-exec" {
    command = <<-EOT
      PGPASSWORD=${azurerm_postgresql_server.postgres.administrator_login_password} psql \
      -h ${azurerm_postgresql_server.postgres.fqdn} \
      -p 5432 \
      -U ${azurerm_postgresql_server.postgres.administrator_login}@${azurerm_postgresql_server.postgres.name} \
      -d ${azurerm_postgresql_database.db.name} \
      -f ${path.module}/../source/init.sql
    EOT
  }
  
  depends_on = [
    azurerm_postgresql_database.db,
    azurerm_postgresql_firewall_rule.aks
  ]
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "aks" {
  name                = "sherpany-law"
  location            = azurerm_resource_group.sherpany_rg.location
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  sku                = "PerGB2018"
  retention_in_days   = 30

  tags = {
    environment = "production"
    project     = "sherpany"
    owner       = "devops"
  }
  depends_on = [azurerm_resource_group.sherpany_rg]
}


# AKS Cluster
resource "azurerm_kubernetes_cluster" "sherpany_aks" {
  name                = "sherpany-aks"
  location            = azurerm_resource_group.sherpany_rg.location
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  dns_prefix          = "sherpanyaks"
  
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
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

  depends_on = [azurerm_resource_group.sherpany_rg, azurerm_log_analytics_workspace.aks]
}

# Container Insights Solution
resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location             = azurerm_resource_group.sherpany_rg.location
  resource_group_name  = azurerm_resource_group.sherpany_rg.name
  workspace_resource_id = azurerm_log_analytics_workspace.aks.id
  workspace_name       = azurerm_log_analytics_workspace.aks.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  depends_on = [azurerm_log_analytics_workspace.aks]
}
# AKS Diagnostic Settings
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diagnostics"
  target_resource_id        = azurerm_kubernetes_cluster.sherpany_aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-controller-manager"
  }

  enabled_log {
    category = "kube-scheduler"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  metric {
    category = "AllMetrics"
  }

  depends_on = [azurerm_kubernetes_cluster.sherpany_aks, azurerm_log_analytics_workspace.aks]
}

# Kubernetes Namespace
resource "kubernetes_namespace" "sherpany" {
  metadata {
    name = "sherpany"
  }
  depends_on = [azurerm_kubernetes_cluster.sherpany_aks]
}

# Database Connection Secret
resource "kubernetes_secret" "postgres_secret" {
  metadata {
    name      = "postgres-secret"
    namespace = "sherpany"
  }

  data = {
    DB_HOST     = azurerm_postgresql_server.postgres.fqdn
    DB_NAME     = azurerm_postgresql_database.db.name
    DB_USER     = "${azurerm_postgresql_server.postgres.administrator_login}@${azurerm_postgresql_server.postgres.name}"
    DB_PASSWORD = azurerm_postgresql_server.postgres.administrator_login_password
    DB_PORT     = "5432"
  }
  depends_on = [kubernetes_namespace.sherpany]
}

# Flask App Deployment
resource "kubernetes_deployment" "flask_app" {
  metadata {
    name      = "flask-app"
    namespace = "sherpany"
    labels = {
      app = "flask-app"
    }
    annotations = {
      "prometheus.io/scrape" = "true"
      "prometheus.io/port"   = "5000"
      "prometheus.io/path"   = "/metrics"
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        app = "flask-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "flask-app"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "5000"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        container {
          name  = "flask-app"
          image = "${azurerm_container_registry.sherpany_acr.login_server}/flask-app:latest"
          
          port {
            container_port = 5000
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.postgres_secret.metadata[0].name
            }
          }

          security_context {
            run_as_user                = 1000
            run_as_non_root           = true
            allow_privilege_escalation = false
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_secret.postgres_secret]
}

# Flask Service
resource "kubernetes_service" "flask_service" {
  metadata {
    name      = "flask-service"
    namespace = "sherpany"
  }

  spec {
    selector = {
      app = "flask-app"
    }

    port {
      port        = 80
      target_port = 5000
    }

    type = "LoadBalancer"
  }
  depends_on = [kubernetes_deployment.flask_app]
}