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
  admin_enabled      = false
  depends_on         = [azurerm_resource_group.sherpany_resources]
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

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [azurerm_kubernetes_cluster.sherpany_aks]
}

resource "helm_release" "prometheus_operator_crds" {
  name       = "prometheus-operator-crds"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  namespace  =  kubernetes_namespace.monitoring.metadata[0].name
  depends_on = [kubernetes_namespace.monitoring]
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  =  kubernetes_namespace.monitoring.metadata[0].name
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
              - targets: ['${data.azurerm_public_ip.vm_pip.ip_address}:9100']
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

  depends_on = [helm_release.prometheus_operator_crds]
}

resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  =  kubernetes_namespace.monitoring.metadata[0].name
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

  depends_on = [helm_release.prometheus, helm_release.prometheus_operator_crds]
}