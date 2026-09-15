variable "cluster_name" {
  description = "Nome do cluster kind (Kubernetes in Docker)"
  type        = string
  default     = "airflow-local"
}

variable "dags_host_path" {
  description = "Caminho no host (sua máquina) com as DAGs, montado no node do kind"
  type        = string
  default     = "./dags"
}

variable "dags_container_path" {
  description = "Caminho dentro do node do kind onde o host_path é montado (e depois exposto aos pods via hostPath volume)"
  type        = string
  default     = "/opt/airflow/dags"
}

variable "airflow_namespace" {
  description = "Namespace do Kubernetes onde o Airflow será instalado"
  type        = string
  default     = "airflow"
}

variable "airflow_release_name" {
  description = "Nome do Helm release do Airflow"
  type        = string
  default     = "airflow"
}

variable "airflow_chart_version" {
  description = "Versão do chart apache-airflow/airflow"
  type        = string
  default     = "1.15.0"
}

variable "airflow_executor" {
  description = "Executor do Airflow (KubernetesExecutor dispensa Redis/Celery workers, ideal para uso local com kind)"
  type        = string
  default     = "KubernetesExecutor"

  validation {
    condition     = contains(["KubernetesExecutor", "CeleryExecutor", "LocalExecutor"], var.airflow_executor)
    error_message = "airflow_executor deve ser KubernetesExecutor, CeleryExecutor ou LocalExecutor."
  }
}

variable "airflow_webserver_host_port" {
  description = "Porta no host (localhost) para acessar a UI do Airflow"
  type        = number
  default     = 8080
}

variable "airflow_webserver_node_port" {
  description = "NodePort do Service do webserver dentro do cluster kind (deve estar entre 30000-32767)"
  type        = number
  default     = 30080
}

variable "admin_username" {
  description = "Usuário admin criado no Airflow"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Senha do usuário admin do Airflow (uso local apenas)"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "admin_email" {
  description = "E-mail do usuário admin do Airflow"
  type        = string
  default     = "admin@example.com"
}

variable "webserver_secret_key" {
  description = "Secret key do webserver. Deixe em branco para gerar uma automaticamente"
  type        = string
  default     = ""
  sensitive   = true
}
