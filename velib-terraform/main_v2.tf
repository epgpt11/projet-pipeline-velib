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

  # Step Functions: Lambda -> Glue Job (sync) -> Clean Crawler
  sfn_definition = {
    Comment = "Velib full pipeline: ingest -> clean -> catalog"
    StartAt = "InvokeIngestLambda"
    States  = {
      InvokeIngestLambda = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.velib_ingest.arn
          Payload      = {}
        }
        Next = "WaitForRaw"
      }

      WaitForRaw = {
        Type    = "Wait"
        Seconds = 15
        Next    = "RunCleanJob"
      }

      RunCleanJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = aws_glue_job.velib_clean_job.name
        }
        Next = "StartCleanCrawler"
      }

      StartCleanCrawler = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:startCrawler"
        Parameters = {
          Name = aws_glue_crawler.velib_clean_crawler.name
        }
        Next = "WaitCrawler"
      }

      WaitCrawler = {
        Type    = "Wait"
        Seconds = 20
        Next    = "GetCrawler"
      }

      GetCrawler = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:glue:getCrawler"
        Parameters = {
          Name = aws_glue_crawler.velib_clean_crawler.name
        }
        Next = "CrawlerDone"
      }

      CrawlerDone = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.Crawler.State"
            StringEquals = "READY"
            Next         = "Success"
          }
        ]
        Default = "WaitCrawler"
      }

      Success = { Type = "Succeed" }
    }
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

# --- S3 prefixes ---
resource "aws_s3_object" "raw_prefix" {
  bucket  = aws_s3_bucket.bucket.id
  key     = "raw/source=velib/"
  content = ""
}

resource "aws_s3_object" "clean_prefix" {
  bucket  = aws_s3_bucket.bucket.id
  key     = "clean/source=velib/"
  content = ""
}

resource "aws_s3_object" "glue_scripts_prefix" {
  bucket  = aws_s3_bucket.bucket.id
  key     = "glue/scripts/"
  content = ""
}

resource "aws_s3_object" "glue_tmp_prefix" {
  bucket  = aws_s3_bucket.bucket.id
  key     = "glue/tmp/"
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

# --- Lambda Function (ingest raw JSON) ---
resource "aws_lambda_function" "velib_ingest" {
  function_name = "velib_ingest_lambda"
  role          = data.aws_iam_role.labrole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }

  tags = local.tags
}

# --- Glue Database ---
resource "aws_glue_catalog_database" "velib_db" {
  name = "velib_db_tf"
}

# --- Upload Glue clean script to S3 ---
resource "aws_s3_object" "glue_clean_script" {
  bucket = aws_s3_bucket.bucket.id
  key    = "glue/scripts/velib_clean.py"
  source = "${path.module}/glue/velib_clean.py"
  etag   = filemd5("${path.module}/glue/velib_clean.py")

  depends_on = [aws_s3_object.glue_scripts_prefix]
}

# --- Glue Job (raw -> clean parquet) ---
resource "aws_glue_job" "velib_clean_job" {
  name     = "velib_clean_job"
  role_arn = data.aws_iam_role.labrole.arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${var.bucket_name}/${aws_s3_object.glue_clean_script.key}"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--TempDir"                          = "s3://${var.bucket_name}/glue/tmp/"
    "--RAW_PATH"                         = "s3://${var.bucket_name}/raw/source=velib/"
    "--CLEAN_PATH"                       = "s3://${var.bucket_name}/clean/source=velib/"
  }

  tags = local.tags

  depends_on = [
    aws_s3_object.glue_clean_script,
    aws_s3_object.clean_prefix,
    aws_s3_object.glue_tmp_prefix
  ]
}

# --- Clean Crawler (discover schema for clean parquet) ---
resource "aws_glue_crawler" "velib_clean_crawler" {
  name          = "velib_clean_crawler"
  role          = data.aws_iam_role.labrole.arn
  database_name = aws_glue_catalog_database.velib_db.name

  s3_target {
    path = "s3://${var.bucket_name}/clean/source=velib/"
  }

  tags = local.tags

  depends_on = [aws_s3_object.clean_prefix]
}

# --- Step Functions state machine ---
resource "aws_sfn_state_machine" "velib_orchestrator" {
  name       = "velib_orchestrator"
  role_arn   = data.aws_iam_role.labrole.arn
  definition = jsonencode(local.sfn_definition)

  tags = local.tags

  depends_on = [
    aws_lambda_function.velib_ingest,
    aws_glue_job.velib_clean_job,
    aws_glue_crawler.velib_clean_crawler
  ]
}

# --- EventBridge Scheduler -> Step Functions (every 15 min) ---
resource "aws_scheduler_schedule" "every_15_min" {
  name = "velib_pipeline_schedule"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(15 minutes)"

  target {
    arn      = aws_sfn_state_machine.velib_orchestrator.arn
    role_arn = data.aws_iam_role.labrole.arn
    input    = jsonencode({})
  }

  depends_on = [aws_sfn_state_machine.velib_orchestrator]
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
