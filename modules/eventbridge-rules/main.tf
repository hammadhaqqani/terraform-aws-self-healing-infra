# =============================================================================
# EventBridge Rules Module
# =============================================================================
# Creates EventBridge rules for event-driven remediation:
# - Security group changes (via AWS Config)
# - RDS instance state changes
# =============================================================================

# -----------------------------------------------------------------------------
# Security Group Change Detection
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "sg_change" {
  count = var.enable_sg_remediation ? 1 : 0

  name        = "${var.environment}-sg-change-detection"
  description = "Detect security group changes that open 0.0.0.0/0 ingress"

  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ec2.amazonaws.com"]
      eventName   = ["AuthorizeSecurityGroupIngress", "ModifySecurityGroupRules"]
    }
  })

  tags = merge(var.tags, { Name = "${var.environment}-sg-change-detection" })
}

resource "aws_cloudwatch_event_target" "sg_remediation" {
  count = var.enable_sg_remediation ? 1 : 0

  rule      = aws_cloudwatch_event_rule.sg_change[0].name
  target_id = "sg-remediation-lambda"
  arn       = var.sg_remediation_lambda_arn
}

resource "aws_lambda_permission" "eventbridge_sg" {
  count = var.enable_sg_remediation ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.sg_remediation_lambda_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sg_change[0].arn
}

# -----------------------------------------------------------------------------
# RDS Instance State Change Detection
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "rds_failure" {
  count = var.enable_rds_recovery ? 1 : 0

  name        = "${var.environment}-rds-failure-detection"
  description = "Detect RDS instance failures and state changes"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event"]
    detail = {
      EventCategories = ["failure", "recovery", "notification"]
    }
  })

  tags = merge(var.tags, { Name = "${var.environment}-rds-failure-detection" })
}

resource "aws_cloudwatch_event_target" "rds_recovery" {
  count = var.enable_rds_recovery ? 1 : 0

  rule      = aws_cloudwatch_event_rule.rds_failure[0].name
  target_id = "rds-recovery-lambda"
  arn       = var.rds_recovery_lambda_arn
}

resource "aws_lambda_permission" "eventbridge_rds" {
  count = var.enable_rds_recovery ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.rds_recovery_lambda_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_failure[0].arn
}
