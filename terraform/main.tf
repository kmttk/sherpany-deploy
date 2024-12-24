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
resource "azurerm_storage_account" "terraform_state" {
  name                     = "sherpanyterraformstate"
  resource_group_name      = azurerm_resource_group.sherpany_rg.name
  location                 = azurerm_resource_group.sherpany_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version         = "TLS1_2"

  depends_on = [azurerm_resource_group.sherpany_rg]

  blob_properties {
    versioning_enabled = true
  }

  tags = {
    environment = "production"
    project     = "sherpany"
    owner       = "devops"
  }
}

# Storage Container for Terraform State
resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.terraform_state.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.terraform_state]
}

# Azure Container Registry
resource "azurerm_container_registry" "sherpany_acr" {
  name                = "sherpanyacr"
  resource_group_name = azurerm_resource_group.sherpany_rg.name
  location            = azurerm_resource_group.sherpany_rg.location
  sku                = "Basic"
  admin_enabled      = false

  depends_on = [azurerm_resource_group.sherpany_rg]

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

resource "azurerm_role_assignment" "acr_pull" {
  principal_id         = azurerm_kubernetes_cluster.sherpany_aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope               = azurerm_container_registry.sherpany_acr.id
}

# resource "kubernetes_deployment" "flask_app" {
#   metadata {
#     name = "flask-app"
#   }

#   spec {
#     replicas = 3

#     selector {
#       match_labels = {
#         app = "flask-app"
#       }
#     }

#     strategy {
#       type = "RollingUpdate"
#       rolling_update {
#         max_unavailable = "25%"
#         max_surge       = "25%"
#       }
#     }

#     template {
#       metadata {
#         labels = {
#           app = "flask-app"
#         }
#       }

#       spec {
#         container {
#           name  = "flask-app"
#           image = "${azurerm_container_registry.sherpany_acr.login_server}/flask-app:latest"
#           port {
#             container_port = 5000
#           }

#           security_context {
#             run_as_non_root             = true
#             allow_privilege_escalation = false
#           }

#           resources {
#             requests = {
#               cpu    = "250m"
#               memory = "128Mi"
#             }
#             limits = {
#               cpu    = "500m"
#               memory = "256Mi"
#             }
#           }

#           liveness_probe {
#             http_get {
#               path = "/health"
#               port = 5000
#             }
#             initial_delay_seconds = 5
#             period_seconds        = 10
#           }

#           readiness_probe {
#             http_get {
#               path = "/health"
#               port = 5000
#             }
#             initial_delay_seconds = 5
#             period_seconds        = 10
#           }
#         }
#       }
#     }
#   }

#   depends_on = [azurerm_kubernetes_cluster.sherpany_aks]
# }

# resource "kubernetes_service" "flask_service" {
#   metadata {
#     name = "flask-service"
#   }

#   spec {
#     selector = {
#       app = "flask-app"
#     }

#     port {
#       protocol    = "TCP"
#       port        = 80
#       target_port = 5000
#     }

#     type = "LoadBalancer"
#   }

#   depends_on = [azurerm_kubernetes_cluster.sherpany_aks]
# }
