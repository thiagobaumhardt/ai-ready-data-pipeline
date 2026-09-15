resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = var.airflow_webserver_node_port
        host_port      = var.airflow_webserver_host_port
        protocol       = "TCP"
      }

      extra_mounts {
        host_path      = var.dags_host_path
        container_path = var.dags_container_path
      }
    }
  }
}

provider "kubernetes" {
  host                   = kind_cluster.this.endpoint
  client_certificate     = kind_cluster.this.client_certificate
  client_key             = kind_cluster.this.client_key
  cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

resource "random_password" "webserver_secret_key" {
  length  = 32
  special = false
}

resource "kubernetes_namespace" "airflow" {
  metadata {
    name = var.airflow_namespace
  }

  depends_on = [kind_cluster.this]
}

locals {
  webserver_secret_key = var.webserver_secret_key != "" ? var.webserver_secret_key : random_password.webserver_secret_key.result

  dags_volume = {
    name = "dags"
    hostPath = {
      path = var.dags_container_path
      type = "DirectoryOrCreate"
    }
  }

  dags_volume_mount = {
    name      = "dags"
    mountPath = "/opt/airflow/dags"
    readOnly  = false
  }

  airflow_values = {
    executor           = var.airflow_executor
    webserverSecretKey = local.webserver_secret_key

    webserver = {
      service = {
        type = "NodePort"
        ports = [
          {
            name       = "airflow-ui"
            port       = 8080
            targetPort = 8080
            nodePort   = var.airflow_webserver_node_port
          }
        ]
      }
      defaultUser = {
        enabled   = true
        username  = var.admin_username
        password  = var.admin_password
        firstName = "Admin"
        lastName  = "User"
        email     = var.admin_email
        role      = "Admin"
      }
      extraVolumes      = [local.dags_volume]
      extraVolumeMounts = [local.dags_volume_mount]
    }

    scheduler = {
      extraVolumes      = [local.dags_volume]
      extraVolumeMounts = [local.dags_volume_mount]
    }

    workers = {
      extraVolumes      = [local.dags_volume]
      extraVolumeMounts = [local.dags_volume_mount]
    }

    triggerer = {
      extraVolumes      = [local.dags_volume]
      extraVolumeMounts = [local.dags_volume_mount]
    }

    dags = {
      persistence = {
        enabled = false
      }
      gitSync = {
        enabled = false
      }
    }

    redis = {
      enabled = var.airflow_executor == "CeleryExecutor"
    }

    postgresql = {
      enabled = true
    }
  }
}

resource "helm_release" "airflow" {
  name       = var.airflow_release_name
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  version    = var.airflow_chart_version
  namespace  = kubernetes_namespace.airflow.metadata[0].name

  timeout       = 900
  wait          = true
  wait_for_jobs = true

  values = [yamlencode(local.airflow_values)]
}
