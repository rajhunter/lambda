output "rest_api_id" {
  value       = aws_api_gateway_rest_api.this.id
  description = "API Gateway REST API ID"
}

output "stage_name" {
  value       = aws_api_gateway_stage.stage.stage_name
  description = "Deployed stage name"
}

output "invoke_url" {
  value       = "https://${aws_api_gateway_rest_api.this.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.stage.stage_name}"
  description = "Base invoke URL for the API"
}

output "lambda_alias_arn" {
  value       = aws_lambda_alias.api.arn
  description = "Lambda alias ARN"
}

output "artifact_bucket" {
  value       = aws_s3_bucket.lambda_artifacts.bucket
  description = "Artifact bucket name"
}
