# =============================================================================
# Complete Example - Self-Healing AWS Infrastructure
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to use S3 backend
  # backend "s3" {
  #   bucket = "my-terraform-state"
  #   key    = "self-healing-infra/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "self-healing-infra"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "self_healing" {
  source = "../../"

  environment         = var.environment
  ec2_instance_ids    = var.ec2_instance_ids
  ecs_cluster_name    = var.ecs_cluster_name
  ecs_service_name    = var.ecs_service_name
  rds_instance_id     = var.rds_instance_id
  notification_emails = var.notification_emails
  slack_webhook_url   = var.slack_webhook_url

  enable_ec2_restart  = true
  enable_ecs_scale    = true
  enable_sg_remediate = true
  enable_rds_recover  = true
}

output "sns_topic_arn" {
  value = module.self_healing.sns_topic_arn
}

output "alarm_arns" {
  value = module.self_healing.cloudwatch_alarm_arns
}
