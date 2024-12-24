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
  name                 = "tfstate"
  storage_account_name = azurerm_storage_account.terraform_state_storage.name
  container_access_type = "private"
  depends_on           = [azurerm_storage_account.terraform_state_storage]
}

resource "azurerm_container_registry" "sherpany_acr" {
  name                     = "sherpanyacr"
  resource_group_name      = azurerm_resource_group.sherpany_rg.name
  location                 = azurerm_resource_group.sherpany_rg.location
  sku                      = "Basic"
  admin_enabled            = false
  tags = {
    environment = "production"
    project     = "sherpany"
    owner       = "devops"
  }
  
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "sherpany_aks" {
  name                = "sherpany-aks"
  location            = azurerm_resource_group.sherpany_rg.location
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  dns_prefix          = "sherpanyaks"

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
}

#ACR Pull Role Assignment
resource "azurerm_role_assignment" "acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.sherpany_aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope               = azurerm_container_registry.sherpany_acr.id
}

# Kubernetes Namespace
resource "kubernetes_namespace" "sherpany" {
  metadata {
    name = "sherpany"
  }
  depends_on = [azurerm_kubernetes_cluster.sherpany_aks]
}

# Flask App Deployment
resource "kubernetes_deployment" "flask_app" {
  metadata {
    name      = "flask-app"
    namespace = "sherpany"
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app = "flask-app"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = "25%"
        max_surge       = "25%"
      }
    }

    template {
      metadata {
        labels = {
          app = "flask-app"
        }
      }

      spec {
        container {
          name  = "flask-app"
          image = "${azurerm_container_registry.sherpany_acr.login_server}/flask-app:latest"
          
          port {
            container_port = 5000
          }

          security_context {
            run_as_user                = 1000
            run_as_non_root           = true
            allow_privilege_escalation = false
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 15
            period_seconds       = 20
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 15
            period_seconds       = 20
          }
        }
      }
    }
  }
  depends_on = [kubernetes_namespace.sherpany]
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