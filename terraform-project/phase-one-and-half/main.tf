data "azurerm_resource_group" "sherpany_resources" {
  name = "sherpany-resources"
}

data "azurerm_resource_group" "vm_rg" {
  name = "sherpany-vm-rg"
}

data "azurerm_kubernetes_cluster" "sherpany_aks" {
  name                = "sherpany-aks"
  resource_group_name = data.azurerm_resource_group.sherpany_resources.name
}

data "azurerm_public_ip" "vm_pip" {
  name                = "ubuntu-pip"
  resource_group_name = data.azurerm_resource_group.vm_rg.name
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [data.azurerm_kubernetes_cluster.sherpany_aks]
}


resource "helm_release" "prometheus_operator_crds" {
  name       = "prometheus-operator-crds"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-operator-crds"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  depends_on = [kubernetes_namespace.monitoring]
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
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "7.0.3"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "adminPassword"
    value = "admin321"  # Change this in production
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

  depends_on = [helm_release.prometheus]
}