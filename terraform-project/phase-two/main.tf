data "azurerm_resource_group" "sherpany_resources" {
  name = "sherpany-resources"
}

# Storage Account
data "azurerm_storage_account" "terraform_state_storage" {
  name                = "sherpanyterraformstate"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

# Storage Container
data "azurerm_storage_container" "terraform_state_container" {
  name                 = "tfstate"
  storage_account_name = data.azurerm_storage_account.terraform_state_storage.name
}

# Container Registry
data "azurerm_container_registry" "sherpany_acr" {
  name                = "sherpanyacr"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

# AKS Cluster data source
data "azurerm_kubernetes_cluster" "sherpany_aks" {
  name                = "sherpany-aks"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

# Log Analytics Workspace
data "azurerm_log_analytics_workspace" "aks-law" {
  name                = "sherpany-law"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

# Azure Database for PostgreSQL
resource "azurerm_postgresql_server" "postgres" {
  name                = "sherpany-psql"
  location            = data.azurerm_resource_group.sherpany_resources.location
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name

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
  depends_on = [data.azurerm_resource_group.sherpany_resources]
}

# Change from data to resource for PostgreSQL Database
resource "azurerm_postgresql_database" "db" {
  name                = "testdb"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
  server_name         = azurerm_postgresql_server.postgres.name
  charset             = "UTF8"
  collation           = "English_United States.1252"
  depends_on          = [ azurerm_postgresql_server.postgres ]
}


locals {
  service_cidr = data.azurerm_kubernetes_cluster.sherpany_aks.network_profile[0].service_cidr
  start_ip     = cidrhost(local.service_cidr, 0)
  end_ip       = cidrhost(local.service_cidr, pow(2, (32 - tonumber(split("/", local.service_cidr)[1]))) - 1)
}

resource "azurerm_postgresql_firewall_rule" "aks_firewall_rule" {
  name                = "aks_firewall_rule"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
  server_name         = "sherpany-psql"
  start_ip_address    = local.start_ip
  end_ip_address      = local.end_ip
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
      -f ${path.module}/../../source/init.sql
    EOT
  }

  depends_on = [azurerm_postgresql_firewall_rule.aks_firewall_rule]
}

# Container Insights Solution
# Container Insights Solution
resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location             = data.azurerm_resource_group.sherpany_resources.location
  resource_group_name  = data.azurerm_resource_group.sherpany_resources.name
  workspace_resource_id = data.azurerm_log_analytics_workspace.aks-law.id
  workspace_name       = data.azurerm_log_analytics_workspace.aks-law.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  depends_on = [data.azurerm_log_analytics_workspace.aks-law]
}
# AKS Diagnostic Settings
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diagnostics"
  target_resource_id        = data.azurerm_kubernetes_cluster.sherpany_aks.id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.aks-law.id

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

  depends_on = [data.azurerm_kubernetes_cluster.sherpany_aks, data.azurerm_log_analytics_workspace.aks-law]
}

#Kubernetes Namespace
resource "kubernetes_namespace" "sherpany" {
  metadata {
    name = "sherpany"
  }
  depends_on = [data.azurerm_kubernetes_cluster.sherpany_aks]
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

resource "kubernetes_secret" "acr_auth" {
  metadata {
    name      = "acr-auth"
    namespace = "sherpany"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      "auths" = {
        "${data.azurerm_container_registry.sherpany_acr.login_server}" = {
          "username" = var.acr_username
          "password" = var.acr_password
          "auth"     = base64encode("${var.acr_username}:${var.acr_password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.sherpany]
}

// Flask App Deployment
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
      }
      spec {
        image_pull_secrets {
          name = "acr-auth"
        }
        container {
          name  = "flask-app"
          image = "${data.azurerm_container_registry.sherpany_acr.login_server}/flask-app:latest"
          
          port {
            name           = "http"
            container_port = 5000
          }

          env_from {
            secret_ref {
              name = "postgres-secret"
            }
          }

            resources {
            limits = {
              cpu    = "500m"    
              memory = "512Mi"   
            }
            requests = {
              cpu    = "125m"     
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
    depends_on = [
    kubernetes_secret.acr_auth,
    kubernetes_secret.postgres_secret,
    kubernetes_namespace.sherpany
  ]
}
// Flask App Service
resource "kubernetes_service" "flask_service" {
  metadata {
    name      = "flask-app-service"
    namespace = "sherpany"
  }

  spec {
    selector = {
      app = "flask-app"
    }

  

    port {
      name        = "http"  
      port        = 80
      target_port = 5000
    }

    type = "LoadBalancer"
  }
    depends_on = [
    kubernetes_secret.acr_auth,
    kubernetes_secret.postgres_secret,
    kubernetes_namespace.sherpany
  ]
}

// Service Monitor for Flask App
resource "kubernetes_manifest" "flask_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "flask-app-monitor"
      namespace = "monitoring"
      labels = {
        release = "prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "flask-app"
        }
      }
      endpoints = [
        {
          port = "http"
          path = "/metrics"
        }
      ]
    }
  }
    depends_on = [
    kubernetes_deployment.flask_app,
    kubernetes_service.flask_service
  ]
}
