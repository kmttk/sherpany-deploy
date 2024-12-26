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

# PostgreSQL Server
data "azurerm_postgresql_server" "postgres" {
  name                = "sherpany-psql"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

# PostgreSQL Database
data "azurerm_postgresql_database" "db" {
  name                = "testdb"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
  server_name         = data.azurerm_postgresql_server.postgres.name
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

# Update PostgreSQL Firewall Rule
resource "azurerm_postgresql_firewall_rule" "aks" {
  name                = "aks"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
  server_name         = data.azurerm_postgresql_server.postgres.name
  start_ip_address    = data.azurerm_kubernetes_cluster.sherpany_aks.network_profile[0].service_cidr
  end_ip_address      = data.azurerm_kubernetes_cluster.sherpany_aks.network_profile[0].service_cidr
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
  
  depends_on = [
    azurerm_postgresql_database.db,
    azurerm_postgresql_firewall_rule.aks
  ]
}

# Container Insights Solution
# Container Insights Solution
resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location             = data.azurerm_resource_group.sherpany_resources.location
  resource_group_name  = data.azurerm_resource_group.sherpany_resources.name
  workspace_resource_id = data.azurerm_log_analytics_workspace.aks-law.id
  workspace_name       = data.azurerm_log_analytics_workspace.aks.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  depends_on = [data.azurerm_log_analytics_workspace.aks-law]
}
# AKS Diagnostic Settings
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diagnostics"
  target_resource_id        = data.azurerm_kubernetes_cluster.aks.id
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
    DB_HOST     = data.azurerm_postgresql_server.postgres.fqdn
    DB_NAME     = data.azurerm_postgresql_database.db.name
    DB_USER     = "${data.azurerm_postgresql_server.postgres.administrator_login}@${data.azurerm_postgresql_server.postgres.name}"
    DB_PASSWORD = data.azurerm_postgresql_server.postgres.administrator_login_password
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
          image = "${data.azurerm_container_registry.sherpany_acr.login_server}/flask-app:latest"
          
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

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    
  }
  depends_on = [kubernete_service.flask_service]
  }

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "25.8.0"

  values = [
    <<-EOT
    serviceMonitorSelectorNilUsesHelmValues: false
    prometheus:
      prometheusSpec:
        serviceMonitorSelector: {}
        additionalScrapeConfigs:
          - job_name: 'vm-node-exporter'
            static_configs:
              - targets: ['${data.azurerm_public_ip.sherpany_vm_ip.ip_address}:9100']
            metrics_path: '/metrics'
            scheme: 'http'
    EOT
  ]

  set {
    name  = "server.persistentVolume.size"
    value = "10Gi"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  depends_on = [kubernetes_namespace.monitoring]
}

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
          port        = "http"
          path        = "/metrics"
          interval    = "15s"
          scrapeTimeout = "10s"
        }
      ]
    }
  }
  depends_on = [helm_release.prometheus]
}

data "azurerm_public_ip" "sherpany_vm_ip" {
  name                = "sherpany-ip"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "7.0.3"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "adminPassword"
    value = "admin321"  # Change this to a secure password
  }

  set {
    name  = "grafana.ini.datasources"
    value = <<-EOT
      [datasources]
      [[datasource]]
      name      = "Prometheus"
      type      = "prometheus"
      url       = "http://prometheus-server.monitoring.svc.cluster.local"
      access    = "proxy"
      isDefault = true
    EOT
  }

  depends_on = [
    helm_release.prometheus,
    kubernetes_namespace.monitoring
  ]
}

# Optional: Output the LoadBalancer IP
output "grafana_ip" {
  value = kubernetes_service.grafana_lb.status[0].load_balancer[0].ingress[0].ip
}