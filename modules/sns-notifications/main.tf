# =============================================================================
# SNS Notifications Module
# =============================================================================

resource "aws_sns_topic" "alerts" {
  name              = "${var.environment}-self-healing-alerts"
  kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : "alias/aws/sns"

  tags = {
    Name        = "${var.environment}-self-healing-alerts"
    Environment = var.environment
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
      },
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.notification_emails)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Optional Slack integration via Lambda
resource "aws_sns_topic_subscription" "slack" {
  count = var.slack_webhook_url != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier[0].arn
}

resource "aws_lambda_function" "slack_notifier" {
  count = var.slack_webhook_url != "" ? 1 : 0

  function_name = "${var.environment}-slack-notifier"
  runtime       = "python3.11"
  handler       = "index.handler"
  role          = aws_iam_role.slack_lambda[0].arn
  timeout       = 10

  filename         = data.archive_file.slack_notifier[0].output_path
  source_code_hash = data.archive_file.slack_notifier[0].output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
    }
  }
}

data "archive_file" "slack_notifier" {
  count = var.slack_webhook_url != "" ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda_slack.zip"

  source {
    content  = <<-PYTHON
import json
import os
import urllib.request

def handler(event, context):
    webhook_url = os.environ["SLACK_WEBHOOK_URL"]
    for record in event.get("Records", []):
        message = record.get("Sns", {}).get("Message", "No message")
        subject = record.get("Sns", {}).get("Subject", "AWS Alert")
        slack_message = {
            "text": f":rotating_light: *{subject}*\n```{message}```"
        }
        req = urllib.request.Request(
            webhook_url,
            data=json.dumps(slack_message).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req)
    return {"statusCode": 200}
PYTHON
    filename = "index.py"
  }
}

resource "aws_iam_role" "slack_lambda" {
  count = var.slack_webhook_url != "" ? 1 : 0

  name = "${var.environment}-slack-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "slack_lambda_basic" {
  count = var.slack_webhook_url != "" ? 1 : 0

  role       = aws_iam_role.slack_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_permission" "sns_slack" {
  count = var.slack_webhook_url != "" ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}
