# Contact-form backend: API Gateway -> Lambda -> SES.
# Independent of the site-hosting phase (S3/CloudFront/Route 53) - doesn't need
# them to exist first, since it's reached directly via its own API Gateway URL.

# SES can only send from/to addresses it has verified. Verifying a single
# mailbox (rather than the whole domain) needs no DNS records, so this works
# before Route 53 is provisioned. AWS emails a confirmation link to
# var.contact_email - it must be clicked before sending will work.
resource "aws_ses_email_identity" "contact" {
  email = var.contact_email
}

data "archive_file" "contact_form" {
  type        = "zip"
  source_file = "${path.module}/../lambda/contact_form.py"
  output_path = "${path.module}/build/contact_form.zip"
}

resource "aws_iam_role" "contact_form_lambda" {
  name = "padillacastillo-contact-form-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "contact_form_lambda" {
  name = "send-ses-and-log"
  role = aws_iam_role.contact_form_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = aws_ses_email_identity.contact.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "contact_form" {
  name              = "/aws/lambda/padillacastillo-contact-form"
  retention_in_days = 14
}

resource "aws_lambda_function" "contact_form" {
  function_name    = "padillacastillo-contact-form"
  role             = aws_iam_role.contact_form_lambda.arn
  handler          = "contact_form.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.contact_form.output_path
  source_code_hash = data.archive_file.contact_form.output_base64sha256

  environment {
    variables = {
      CONTACT_EMAIL = var.contact_email
    }
  }

  depends_on = [aws_cloudwatch_log_group.contact_form]
}

resource "aws_apigatewayv2_api" "contact_form" {
  name          = "padillacastillo-contact-form"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origin
    allow_methods = ["POST"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "contact_form" {
  api_id                 = aws_apigatewayv2_api.contact_form.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact_form.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "contact_form" {
  api_id    = aws_apigatewayv2_api.contact_form.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.contact_form.id}"
}

resource "aws_apigatewayv2_stage" "contact_form" {
  api_id      = aws_apigatewayv2_api.contact_form.id
  name        = "$default"
  auto_deploy = true

  # Personal contact form - a low ceiling is plenty and blunts spam floods.
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_lambda_permission" "contact_form_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact_form.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.contact_form.execution_arn}/*/*"
}

output "contact_form_api_url" {
  description = "Paste this into site/js/contact.js as CONTACT_API_URL, then append /contact"
  value       = aws_apigatewayv2_stage.contact_form.invoke_url
}
