###############################################
# Provider & Region
###############################################
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

###############################################
# S3 bucket for Lambda artifacts
###############################################
locals {
  bucket_name = "${var.project_name}-lambda-artifacts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = { Project = var.project_name }
}

resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket                  = aws_s3_bucket.lambda_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload the Lambda deployment ZIP
resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  key    = "lambda/${var.project_name}.zip"
  source = var.lambda_zip_path
  etag   = filemd5(var.lambda_zip_path)

  depends_on = [
    aws_s3_bucket_public_access_block.lambda_artifacts
  ]
}

###############################################
# IAM role for Lambda
###############################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = { Project = var.project_name }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################################
# Lambda function (Java 17)
###############################################
resource "aws_lambda_function" "api_fn" {
  function_name = "${var.project_name}-api"
  role          = aws_iam_role.lambda_role.arn

  s3_bucket = aws_s3_bucket.lambda_artifacts.bucket
  s3_key    = aws_s3_object.lambda_zip.key

  handler = "com.custmngt.customer_management.StreamLambdaHandler::handleRequest"
  runtime = "java17"

  # Keep < 29s for API Gateway; 20s is safe
  timeout     = 20
  memory_size = 2048

  publish          = true
  source_code_hash = filebase64sha256(var.lambda_zip_path)
  architectures    = [var.architecture] # "x86_64" or "arm64"

  # Optional but very effective for Java (works on published versions)
  snap_start {
    apply_on = "PublishedVersions"
  }

  environment {
    variables = {
      JAVA_TOOL_OPTIONS = "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_exec,
    aws_s3_object.lambda_zip
  ]

  tags = { Project = var.project_name }
}

# Point an alias at the newly published version
resource "aws_lambda_alias" "api" {
  name             = "live"
  description      = "Live alias for ${var.project_name} API"
  function_name    = aws_lambda_function.api_fn.function_name
  function_version = aws_lambda_function.api_fn.version
}

###############################################
# API Gateway (REST) - ANY proxy + root
###############################################
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project_name}-api"
  description = "REST API for ${var.project_name} backed by Lambda proxy"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  tags = { Project = var.project_name }
}

# Root method (for /)
resource "aws_api_gateway_method" "root_any" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "root_any" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_method.root_any.resource_id
  http_method = aws_api_gateway_method.root_any.http_method

  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_alias.api.arn}/invocations"
}

# Proxy resource /{proxy+}
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "proxy_any" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_any.http_method

  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_alias.api.arn}/invocations"
}

# Deployment + Stage
resource "aws_api_gateway_deployment" "dep" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Force redeploy when alias/version/integration changes
  triggers = {
    redeploy = sha1(jsonencode({
      lambda_version = aws_lambda_alias.api.function_version
      root_uri       = aws_api_gateway_integration.root_any.uri
      proxy_uri      = aws_api_gateway_integration.proxy_any.uri
      methods        = ["ANY"]
      stage          = var.stage_name
    }))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.root_any,
    aws_api_gateway_integration.proxy_any
  ]
}

resource "aws_api_gateway_stage" "stage" {
  stage_name    = var.stage_name
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.dep.id

  tags = { Project = var.project_name }
}

###############################################
# Permission: allow API Gateway to invoke Lambda
###############################################
resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_alias.api.arn
  principal     = "apigateway.amazonaws.com"

  # Wildcard stage / method / resource for this REST API
  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*/*"
}

###############################################
# (Optional) Provisioned Concurrency for warm starts
###############################################
# resource "aws_lambda_provisioned_concurrency_config" "pc" {
#   function_name                     = aws_lambda_alias.api.function_name
#   qualifier                         = aws_lambda_alias.api.name
#   provisioned_concurrent_executions = 1
# }
