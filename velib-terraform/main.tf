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

  # ============================================================
  # Step Functions #1 : Pipeline data
  # Lambda ingest -> Wait -> Glue clean job (sync) -> Crawler clean (poll)
  # ============================================================
  sfn_pipeline_definition = {
    Comment = "Velib pipeline: ingest -> clean -> crawl"
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

  # ============================================================
  # Step Functions #2 : KPI views (Athena) - PAS planifiée (manual demo)
  # Exécute uniquement des CREATE OR REPLACE VIEW
  # ============================================================
  kpi_queries = {
    kpi_taux_remplissage = <<-SQL
      CREATE OR REPLACE VIEW kpi_taux_remplissage AS
      SELECT
        ingested_ts,
        station_id,
        name,
        arrondissement,
        bikes_i AS bikes,
        docks_i AS docks,
        (bikes_i + docks_i) AS capacity,
        fill_rate
      FROM ${var.clean_table_name}
      WHERE is_installed_i = 1
        AND bikes_i IS NOT NULL
        AND docks_i IS NOT NULL;
    SQL

    kpi_shortage = <<-SQL
      CREATE OR REPLACE VIEW kpi_shortage AS
      SELECT
        ingested_ts,
        station_id,
        name,
        arrondissement,
        bikes_i,
        docks_i,
        fill_rate
      FROM ${var.clean_table_name}
      WHERE is_installed_i = 1
        AND bikes_i = 0;
    SQL

    kpi_station_saturation = <<-SQL
      CREATE OR REPLACE VIEW kpi_station_saturation AS
      SELECT
        ingested_ts,
        station_id,
        name,
        arrondissement,
        bikes_i,
        docks_i,
        fill_rate
      FROM ${var.clean_table_name}
      WHERE is_installed_i = 1
        AND (docks_i = 0 OR fill_rate >= 0.9);
    SQL

    kpi_saturation_par_arrondissement = <<-SQL
      CREATE OR REPLACE VIEW kpi_saturation_par_arrondissement AS
      SELECT
        arrondissement,
        COUNT(*) AS station_count,
        AVG(fill_rate) AS avg_fill_rate,
        SUM(CASE WHEN bikes_i = 0 THEN 1 ELSE 0 END) AS shortage_count,
        SUM(CASE WHEN docks_i = 0 OR fill_rate >= 0.9 THEN 1 ELSE 0 END) AS saturation_count
      FROM ${var.clean_table_name}
      WHERE is_installed_i = 1
      GROUP BY arrondissement;
    SQL

    kpi_top10_2hour = <<-SQL
      CREATE OR REPLACE VIEW kpi_top10_2hour AS
      WITH recent AS (
        SELECT *
        FROM ${var.clean_table_name}
        WHERE ingested_ts >= date_add('hour', -2, current_timestamp)
          AND is_installed_i = 1
      )
      SELECT
        station_id,
        MAX(name) AS name,
        MAX(arrondissement) AS arrondissement,
        AVG(fill_rate) AS avg_fill_rate,
        SUM(CASE WHEN bikes_i = 0 THEN 1 ELSE 0 END) AS shortage_hits,
        SUM(CASE WHEN docks_i = 0 THEN 1 ELSE 0 END) AS saturation_hits,
        (
          SUM(CASE WHEN bikes_i = 0 THEN 2 ELSE 0 END) +
          SUM(CASE WHEN docks_i = 0 THEN 2 ELSE 0 END) +
          SUM(CASE WHEN fill_rate >= 0.9 THEN 1 ELSE 0 END)
        ) AS critical_score
      FROM recent
      GROUP BY station_id
      ORDER BY critical_score DESC
      LIMIT 10;
    SQL
  }

  sfn_kpi_definition = {
    Comment = "Create/Update Athena KPI views"
    StartAt = "CreateKpiTauxRemplissage"
    States  = {
      CreateKpiTauxRemplissage = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryString = local.kpi_queries.kpi_taux_remplissage
          WorkGroup   = aws_athena_workgroup.wg.name
          QueryExecutionContext = {
            Database = aws_glue_catalog_database.velib_db.name
          }
          ResultConfiguration = {
            OutputLocation = "s3://${var.bucket_name}/athena-results/"
          }
        }
        Next = "CreateKpiShortage"
      }

      CreateKpiShortage = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryString = local.kpi_queries.kpi_shortage
          WorkGroup   = aws_athena_workgroup.wg.name
          QueryExecutionContext = {
            Database = aws_glue_catalog_database.velib_db.name
          }
          ResultConfiguration = {
            OutputLocation = "s3://${var.bucket_name}/athena-results/"
          }
        }
        Next = "CreateKpiStationSaturation"
      }

      CreateKpiStationSaturation = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryString = local.kpi_queries.kpi_station_saturation
          WorkGroup   = aws_athena_workgroup.wg.name
          QueryExecutionContext = {
            Database = aws_glue_catalog_database.velib_db.name
          }
          ResultConfiguration = {
            OutputLocation = "s3://${var.bucket_name}/athena-results/"
          }
        }
        Next = "CreateKpiArrondissement"
      }

      CreateKpiArrondissement = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryString = local.kpi_queries.kpi_saturation_par_arrondissement
          WorkGroup   = aws_athena_workgroup.wg.name
          QueryExecutionContext = {
            Database = aws_glue_catalog_database.velib_db.name
          }
          ResultConfiguration = {
            OutputLocation = "s3://${var.bucket_name}/athena-results/"
          }
        }
        Next = "CreateKpiTop10"
      }

      CreateKpiTop10 = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryString = local.kpi_queries.kpi_top10_2hour
          WorkGroup   = aws_athena_workgroup.wg.name
          QueryExecutionContext = {
            Database = aws_glue_catalog_database.velib_db.name
          }
          ResultConfiguration = {
            OutputLocation = "s3://${var.bucket_name}/athena-results/"
          }
        }
        Next = "Success"
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

# --- S3 prefixes (repérage) ---
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

# --- Packager le code Lambda INGEST ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "velib_ingest" {
  function_name = var.lambda_ingest_name
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
  name = var.glue_db_name
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
  name     = var.glue_clean_job_name
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

# --- Clean Crawler (catalog table source_velib) ---
resource "aws_glue_crawler" "velib_clean_crawler" {
  name          = var.glue_clean_crawler_name
  role          = data.aws_iam_role.labrole.arn
  database_name = aws_glue_catalog_database.velib_db.name

  s3_target {
    path = "s3://${var.bucket_name}/clean/source=velib/"
  }

  tags = local.tags

  depends_on = [aws_s3_object.clean_prefix]
}

# --- Athena Workgroup ---
resource "aws_athena_workgroup" "wg" {
  name = var.athena_workgroup_name

  configuration {
    result_configuration {
      output_location = "s3://${var.bucket_name}/athena-results/"
    }
  }

  tags = local.tags
}

# --- Step Functions #1: pipeline ---
resource "aws_sfn_state_machine" "velib_pipeline" {
  name       = var.sfn_pipeline_name
  role_arn   = data.aws_iam_role.labrole.arn
  definition = jsonencode(local.sfn_pipeline_definition)

  tags = local.tags

  depends_on = [
    aws_lambda_function.velib_ingest,
    aws_glue_job.velib_clean_job,
    aws_glue_crawler.velib_clean_crawler
  ]
}

# --- Scheduler: every 15 minutes -> SFN #1 ---
resource "aws_scheduler_schedule" "every_15_min" {
  name = var.scheduler_name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(15 minutes)"

  target {
    arn      = aws_sfn_state_machine.velib_pipeline.arn
    role_arn = data.aws_iam_role.labrole.arn
    input    = jsonencode({})
  }

  depends_on = [aws_sfn_state_machine.velib_pipeline]
}

# --- Step Functions #2: KPI views (manual) ---
resource "aws_sfn_state_machine" "velib_kpi_views" {
  name       = var.sfn_kpi_name
  role_arn   = data.aws_iam_role.labrole.arn
  definition = jsonencode(local.sfn_kpi_definition)

  tags = local.tags

  depends_on = [
    aws_athena_workgroup.wg,
    aws_glue_catalog_database.velib_db
  ]
}