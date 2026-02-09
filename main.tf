# =============================================================================
# Self-Healing AWS Infrastructure - Root Module
# =============================================================================
# Orchestrates CloudWatch alarms, SNS notifications, Lambda remediation
# functions, and EventBridge rules for automated infrastructure recovery.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# SNS Notifications
# -----------------------------------------------------------------------------
module "notifications" {
  source = "./modules/sns-notifications"

  environment         = var.environment
  notification_emails = var.notification_emails
  slack_webhook_url   = var.slack_webhook_url
  kms_key_arn         = var.kms_key_arn
}

# -----------------------------------------------------------------------------
# Lambda Remediation Functions
# -----------------------------------------------------------------------------
module "remediation" {
  source = "./modules/lambda-remediation"

  environment         = var.environment
  sns_topic_arn       = module.notifications.topic_arn
  enable_ec2_restart  = var.enable_ec2_restart
  enable_ecs_scale    = var.enable_ecs_scale
  enable_sg_remediate = var.enable_sg_remediate
  enable_rds_recover  = var.enable_rds_recover

  ec2_instance_ids = var.ec2_instance_ids
  ecs_cluster_name = var.ecs_cluster_name
  ecs_service_name = var.ecs_service_name
  rds_instance_id  = var.rds_instance_id

  tags = var.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------
module "alarms" {
  source = "./modules/cloudwatch-alarms"

  environment      = var.environment
  ec2_instance_ids = var.ec2_instance_ids
  ecs_cluster_name = var.ecs_cluster_name
  ecs_service_name = var.ecs_service_name
  rds_instance_id  = var.rds_instance_id
  sns_topic_arn    = module.notifications.topic_arn

  ec2_lambda_arn = var.enable_ec2_restart ? module.remediation.ec2_lambda_arn : ""
  ecs_lambda_arn = var.enable_ecs_scale ? module.remediation.ecs_lambda_arn : ""

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EventBridge Rules (Event-Driven Remediation)
# -----------------------------------------------------------------------------
module "eventbridge" {
  source = "./modules/eventbridge-rules"

  environment = var.environment

  sg_remediation_lambda_arn = var.enable_sg_remediate ? module.remediation.sg_lambda_arn : ""
  rds_recovery_lambda_arn   = var.enable_rds_recover ? module.remediation.rds_lambda_arn : ""

  enable_sg_remediation = var.enable_sg_remediate
  enable_rds_recovery   = var.enable_rds_recover

  tags = var.tags
}
