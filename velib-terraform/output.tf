output "bucket_name" {
  value = aws_s3_bucket.bucket.bucket
}

output "lambda_ingest" {
  value = aws_lambda_function.velib_ingest.function_name
}

output "glue_database" {
  value = aws_glue_catalog_database.velib_db.name
}

output "glue_clean_job" {
  value = aws_glue_job.velib_clean_job.name
}

output "glue_clean_crawler" {
  value = aws_glue_crawler.velib_clean_crawler.name
}

output "athena_workgroup" {
  value = aws_athena_workgroup.wg.name
}

output "sfn_pipeline_arn" {
  value = aws_sfn_state_machine.velib_pipeline.arn
}

output "sfn_kpi_arn" {
  value = aws_sfn_state_machine.velib_kpi_views.arn
}

output "scheduler_name" {
  value = aws_scheduler_schedule.every_15_min.name
}