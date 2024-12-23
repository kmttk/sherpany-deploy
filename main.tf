# Azure Resource Group
resource "azurerm_resource_group" "sherpany_rg" {
  name     = "sherpany-rg"
  location = "West Europe"
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
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
  }
}

resource "azurerm_container_registry" "sherpany_acr" {
  name                = "sherpanyacr"
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  location            = azurerm_resource_group.sherpany_rg.location
  sku                 = "Basic"
  admin_enabled       = false 
}

resource "azurerm_role_assignment" "acr_pull" {
  principal_id   = azurerm_kubernetes_cluster.sherpany_aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope          = azurerm_container_registry.sherpany_acr.id
}


provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.sherpany_aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.sherpany_aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.sherpany_aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.sherpany_aks.kube_config.0.cluster_ca_certificate)
}

resource "kubernetes_deployment" "flask_app" {
  metadata {
    name = "flask-app"
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
          ports {
            container_port = 5000
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
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "flask_service" {
  metadata {
    name = "flask-service"
  }

  spec {
    selector = {
      app = "flask-app"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5000
    }

    type = "LoadBalancer"
  }
}
