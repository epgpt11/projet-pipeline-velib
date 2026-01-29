variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type    = string
  # Doit être UNIQUE mondialement
  default = "velib-insights-naw-seu-2326-demo"
}

variable "project" {
  type    = string
  default = "velib-insights"
}

variable "owner" {
  type    = string
  default = "team-naw-seu"
}

variable "course" {
  type    = string
  default = "data-pipeline-episen"
}

# LabRole uniquement 
variable "lab_role_name" {
  type    = string
  default = "LabRole"
}

# Noms ressources
variable "lambda_ingest_name" {
  type    = string
  default = "velib_ingest_lambda"
}

variable "glue_db_name" {
  type    = string
  default = "velib_db_tf"
}

variable "glue_clean_job_name" {
  type    = string
  default = "velib_clean_job"
}

variable "glue_clean_crawler_name" {
  type    = string
  default = "velib_clean_crawler"
}

variable "sfn_pipeline_name" {
  type    = string
  default = "velib_orchestrator"
}

variable "sfn_kpi_name" {
  type    = string
  default = "velib_kpi_views"
}

variable "scheduler_name" {
  type    = string
  default = "velib_pipeline_schedule"
}

variable "athena_workgroup_name" {
  type    = string
  default = "velib_workgroup"
}

# Table clean créée par le crawler 
variable "clean_table_name" {
  type    = string
  default = "source_velib"
}