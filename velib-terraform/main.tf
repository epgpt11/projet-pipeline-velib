terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  tags = {
    project = var.project
    owner   = var.owner
    course  = var.course
  }
}

# --- Réutiliser le rôle existant du lab (PAS de CreateRole) ---
data "aws_iam_role" "labrole" {
  name = var.lab_role_name
}

# --- S3 bucket ---
resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket                  = aws_s3_bucket.bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Dossiers logiques (optionnel, juste pour le repérage)
resource "aws_s3_object" "raw_prefix" {
  bucket  = aws_s3_bucket.bucket.id
  key     = "raw/source=velib/"
  content = ""
}

resource "aws_s3_object" "athena_results_prefix" {
  bucket  = aws_s3_bucket.bucket.id
  key     = "athena-results/"
  content = ""
}

# --- Packager le code Lambda ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# --- Lambda Function ---
resource "aws_lambda_function" "velib_ingest" {
  function_name = "velib_ingest_lambda"
  role          = data.aws_iam_role.labrole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout      = 30
  memory_size  = 256

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }

  tags = local.tags
}

# --- EventBridge Scheduler (toutes les 15 minutes) ---
# Si ton lab n'autorise pas Scheduler, on basculera vers cloudwatch_event_rule
resource "aws_scheduler_schedule" "every_15_min" {
  name = "velib_ingest_schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(15 minutes)"

  target {
    arn      = aws_lambda_function.velib_ingest.arn
    role_arn = data.aws_iam_role.labrole.arn

    input = jsonencode({})
  }
}

# Permission pour que scheduler invoke Lambda
resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowExecutionFromScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.velib_ingest.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.every_15_min.arn
}

# --- Glue Database ---
resource "aws_glue_catalog_database" "velib_db" {
  name = "velib_db"
}

# --- Glue Crawler ---
resource "aws_glue_crawler" "velib_crawler" {
  name          = "velib_raw_crawler"
  role          = data.aws_iam_role.labrole.arn
  database_name = aws_glue_catalog_database.velib_db.name

  s3_target {
    path = "s3://${var.bucket_name}/raw/source=velib/"
  }

  tags = local.tags
}

# --- Athena Workgroup ---
resource "aws_athena_workgroup" "wg" {
  name = "velib_workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"
    }
  }

  tags = local.tags
}