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

      # The dbt project. Only needs to exist on the node's filesystem - the
      # "dbt" DAG's KubernetesPodOperator mounts it into its own pod
      # directly (a hostPath volume that reads this node path). It's a
      # separate pod running a third-party image, not part of Airflow's own
      # git-sync setup below, so it keeps its own simple local mount.
      extra_mounts {
        host_path      = var.dbt_host_path
        container_path = var.dbt_container_path
      }

      dynamic "extra_mounts" {
        for_each = var.gcp_credentials_file != "" ? [1] : []
        content {
          host_path      = var.gcp_credentials_file
          container_path = "/opt/airflow/gcp/key.json"
        }
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

  # This chart's git-sync feature is built into every pod template already
  # (scheduler, dag-processor, workers, ...), so it needs no extraVolumes
  # from us. We sync the whole repo (not just airflow/dags), so DAGs and
  # the ingestion package always come from the same commit. That means the
  # DAGs themselves end up one level deeper than Airflow expects by
  # default, so we point AIRFLOW__CORE__DAGS_FOLDER at the right subfolder,
  # and PYTHONPATH at the repo root so `import ingestion...` still works.
  repo_env = [
    { name = "PYTHONPATH", value = var.dags_repo_mount_path },
    { name = "AIRFLOW__CORE__DAGS_FOLDER", value = "${var.dags_repo_mount_path}/airflow/dags" },
  ]

  gcp_credentials_enabled = var.gcp_credentials_file != ""

  gcp_credentials_volume = local.gcp_credentials_enabled ? [{
    name = "gcp-credentials"
    hostPath = {
      path = "/opt/airflow/gcp/key.json"
      type = "File"
    }
  }] : []

  gcp_credentials_volume_mount = local.gcp_credentials_enabled ? [{
    name      = "gcp-credentials"
    mountPath = "/opt/airflow/gcp/key.json"
    readOnly  = true
  }] : []

  # Dataset per table lives in ingestion/config/tables.yml, not here - that's
  # the single source of truth for where each table lands and its
  # write_disposition (append/truncate).
  worker_env = concat(
    local.repo_env,
    [
      { name = "GCS_BUCKET_NAME", value = var.gcs_bucket_name },
      { name = "GCP_PROJECT_ID", value = var.gcp_project_id },
    ],
    local.gcp_credentials_enabled ? [{ name = "GOOGLE_APPLICATION_CREDENTIALS", value = "/opt/airflow/gcp/key.json" }] : []
  )

  airflow_values = {
    executor           = var.airflow_executor
    webserverSecretKey = local.webserver_secret_key

    # Airflow 3's chart serves the UI/API from the "apiServer" component, not
    # "webserver" (that's Airflow 2 naming, kept only for defaultUser, which
    # the createUserJob template still reads from webserver.defaultUser).
    webserver = {
      defaultUser = {
        enabled   = true
        username  = var.admin_username
        password  = var.admin_password
        firstName = "Admin"
        lastName  = "User"
        email     = var.admin_email
        role      = "Admin"
      }
    }

    apiServer = {
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
      env = local.repo_env
      # Default failureThreshold (6) x periodSeconds (10) = 60s is too tight
      # for a local kind cluster on modest hardware; the api-server can take
      # longer than that to bind on first boot and gets stuck restarting.
      startupProbe = {
        failureThreshold = 30
      }
    }

    scheduler = {
      env = local.repo_env
    }

    # Airflow 3 splits DAG parsing out of the scheduler into its own
    # dagProcessor component/pod - it needs the same env, otherwise it
    # looks for DAGs in the wrong folder and nothing shows up in the UI.
    dagProcessor = {
      env = local.repo_env
    }

    workers = {
      extraVolumes      = local.gcp_credentials_volume
      extraVolumeMounts = local.gcp_credentials_volume_mount
      env               = local.worker_env
    }

    triggerer = {
      env = local.repo_env
    }

    dags = {
      # Where the synced repo lands in every pod. Airflow's own default
      # (dags at $AIRFLOW_HOME/dags) doesn't fit here, since we sync more
      # than just the dags folder - see AIRFLOW__CORE__DAGS_FOLDER above.
      mountPath = var.dags_repo_mount_path

      persistence = {
        enabled = false
      }

      # Same mechanism a real cluster uses: nodes never see your laptop's
      # disk, so DAGs (and here, the whole repo) come from git instead. A
      # sidecar container the chart adds on its own pulls this repo/branch
      # on a timer and keeps every Airflow pod in sync.
      gitSync = {
        enabled = true
        repo    = var.dags_repo_url
        branch  = var.dags_repo_branch
        rev     = "HEAD"
        depth   = 1
        subPath = ""
        period  = var.dags_repo_sync_period
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

  # wait=false is intentional: the chart runs DB migrations as a
  # post-install Helm hook, and the main pods (scheduler, webserver, ...)
  # block in an init container until migrations are done. With wait=true,
  # Helm waits for those main pods to become ready BEFORE running the
  # post-install hook - a deadlock. With wait=false, Helm still runs the
  # hook synchronously (and this resource still waits for that), it just
  # doesn't also block on the main pods' readiness; they converge shortly
  # after, once the migration hook completes.
  timeout = 900
  wait    = false

  values = [yamlencode(local.airflow_values)]
}
