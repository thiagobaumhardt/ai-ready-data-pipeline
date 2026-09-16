variable "cluster_name" {
  description = "Name of the kind cluster (Kubernetes in Docker)"
  type        = string
  default     = "airflow-local"
}

variable "dags_host_path" {
  description = "Local (host) path with the DAGs, mounted into the kind node. Deliberately outside the terraform tree: DAGs are pipeline code, not infra"
  type        = string
  default     = "../../airflow/dags"
}

variable "dags_container_path" {
  description = "Path inside the kind node where host_path is mounted (and then exposed to pods via a hostPath volume)"
  type        = string
  default     = "/opt/airflow/dags"
}

variable "airflow_namespace" {
  description = "Kubernetes namespace where Airflow will be installed"
  type        = string
  default     = "airflow"
}

variable "airflow_release_name" {
  description = "Name of the Airflow Helm release"
  type        = string
  default     = "airflow"
}

variable "airflow_chart_version" {
  description = "Version of the apache-airflow/airflow chart (1.17.0+ installs Airflow 3 by default; this project's DAGs use the airflow.sdk TaskFlow API, which is Airflow 3 only)"
  type        = string
  default     = "1.19.0"
}

variable "gcs_bucket_name" {
  description = "GCS bucket the fhir_ingestion DAG writes raw data to (must be the same bucket created by the GCP Terraform root, see terraform/variables.tf bucket_name)"
  type        = string
  default     = "data-lake"
}

variable "gcp_credentials_file" {
  description = "Local path to the GCP service account JSON key (the same one used in terraform/keys/), mounted into the Airflow pods to authenticate against GCS and BigQuery. Leave blank to skip mounting credentials (the upload/load tasks fail at runtime until this is set)"
  type        = string
  default     = ""
}

variable "gcp_project_id" {
  description = "GCP project ID (same project_id as the GCP Terraform root), used by the fhir_ingestion DAG's load_to_bigquery task"
  type        = string
  default     = ""
}

variable "airflow_executor" {
  description = "Airflow executor (KubernetesExecutor skips Redis/Celery workers, ideal for local use with kind)"
  type        = string
  default     = "KubernetesExecutor"

  validation {
    condition     = contains(["KubernetesExecutor", "CeleryExecutor", "LocalExecutor"], var.airflow_executor)
    error_message = "airflow_executor must be KubernetesExecutor, CeleryExecutor, or LocalExecutor."
  }
}

variable "airflow_webserver_host_port" {
  description = "Host (localhost) port to access the Airflow UI"
  type        = number
  default     = 8080
}

variable "airflow_webserver_node_port" {
  description = "NodePort of the webserver Service inside the kind cluster (must be between 30000-32767)"
  type        = number
  default     = 30080
}

variable "admin_username" {
  description = "Admin user created in Airflow"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Password for the Airflow admin user (local use only)"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "admin_email" {
  description = "Email for the Airflow admin user"
  type        = string
  default     = "admin@example.com"
}

variable "webserver_secret_key" {
  description = "Webserver secret key. Leave blank to generate one automatically"
  type        = string
  default     = ""
  sensitive   = true
}
