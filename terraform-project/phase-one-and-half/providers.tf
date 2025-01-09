provider "azurerm" {
  features {}
  subscription_id = var.azure_subscription_id
  client_id       = var.azure_client_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id
}
provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.sherpany_aks.kube_config[0].cluster_ca_certificate)
  }
}

provider "github" {
  token = var.github_tokens
  owner = var.github_owner
}