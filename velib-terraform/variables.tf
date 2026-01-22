variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  type    = string
  default = "velib-insights-naw-seu-2326"
}

variable "project" { type = string  default = "velib-insights" }
variable "owner"   { type = string  default = "team-naw-seu" }
variable "course"  { type = string  default = "data-pipeline-episen" }

# IMPORTANT: rôle IAM existant dans le lab
variable "lab_role_name" {
  type    = string
  default = "LabRole"
}