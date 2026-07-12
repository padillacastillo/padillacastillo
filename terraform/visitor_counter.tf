# Visitor counter backend: API Gateway -> Lambda -> DynamoDB.
# Counts unique visitors by keying on an HMAC of the source IP rather than the
# IP itself, so no raw IP address is ever persisted (see README for why).
# Independent of the site-hosting phase - reached directly via its own API
# Gateway URL, same as the contact form.

# Only this Lambda ever sees this key, and it's what makes the stored hashes
# unreversible - without it, IPv4's small address space (~4.3B) makes a plain
# hash of an IP trivially reversible with a precomputed table.
resource "random_password" "visitor_ip_hmac_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "visitor_ip_hmac_key" {
  name        = "padillacastillo-visitor-ip-hmac-key"
  description = "Keys the HMAC used to dedupe visitor IPs, so raw IPs are never stored in DynamoDB."
}

resource "aws_secretsmanager_secret_version" "visitor_ip_hmac_key" {
  secret_id     = aws_secretsmanager_secret.visitor_ip_hmac_key.id
  secret_string = random_password.visitor_ip_hmac_key.result
}

# Single table, two item shapes: one row holds the running total
# (pk = "COUNT"), one row per unique visitor (pk = "VISITOR#<hmac>"). The
# per-visitor rows are what make a repeat visit from the same IP a no-op
# instead of another increment. No TTL - "unique" here means unique for the
# lifetime of the site, not per day, so those rows are kept forever.
resource "aws_dynamodb_table" "visitor_counter" {
  name         = "padillacastillo-visitor-counter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }
}

data "archive_file" "visitor_counter" {
  type        = "zip"
  source_file = "${path.module}/../lambda/visitor_counter.py"
  output_path = "${path.module}/build/visitor_counter.zip"
}

resource "aws_iam_role" "visitor_counter_lambda" {
  name = "padillacastillo-visitor-counter-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "visitor_counter_lambda" {
  name = "read-write-counter-table-and-hmac-secret"
  role = aws_iam_role.visitor_counter_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = aws_secretsmanager_secret.visitor_ip_hmac_key.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "visitor_counter" {
  name              = "/aws/lambda/padillacastillo-visitor-counter"
  retention_in_days = 14
}

resource "aws_lambda_function" "visitor_counter" {
  function_name    = "padillacastillo-visitor-counter"
  role             = aws_iam_role.visitor_counter_lambda.arn
  handler          = "visitor_counter.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.visitor_counter.output_path
  source_code_hash = data.archive_file.visitor_counter.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
      SECRET_ARN = aws_secretsmanager_secret.visitor_ip_hmac_key.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.visitor_counter]
}

resource "aws_apigatewayv2_api" "visitor_counter" {
  name          = "padillacastillo-visitor-counter"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origin
    allow_methods = ["GET"]
  }
}

resource "aws_apigatewayv2_integration" "visitor_counter" {
  api_id                 = aws_apigatewayv2_api.visitor_counter.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "visitor_counter" {
  api_id    = aws_apigatewayv2_api.visitor_counter.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter.id}"
}

resource "aws_apigatewayv2_stage" "visitor_counter" {
  api_id      = aws_apigatewayv2_api.visitor_counter.id
  name        = "$default"
  auto_deploy = true

  # Personal resume site - a low ceiling is plenty and blunts a bot flood
  # from inflating the count.
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_lambda_permission" "visitor_counter_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.visitor_counter.execution_arn}/*/*"
}

output "visitor_counter_api_url" {
  description = "Paste this into site/js/visitor-counter.js as VISITOR_COUNTER_API_URL, then append /count"
  value       = aws_apigatewayv2_stage.visitor_counter.invoke_url
}
