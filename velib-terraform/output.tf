output "bucket_name" {
  value = var.bucket_name
}

output "lambda_name" {
  value = aws_lambda_function.velib_ingest.function_name
}

output "scheduler_name" {
  value = aws_scheduler_schedule.every_15_min.name
}

output "glue_database" {
  value = aws_glue_catalog_database.velib_db.name
}

output "glue_crawler" {
  value = aws_glue_crawler.velib_crawler.name
}

output "athena_workgroup" {
  value = aws_athena_workgroup.wg.name
}