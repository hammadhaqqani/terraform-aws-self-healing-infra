variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "ec2_instance_ids" {
  type    = list(string)
  default = []
}

variable "ecs_cluster_name" {
  type    = string
  default = ""
}

variable "ecs_service_name" {
  type    = string
  default = ""
}

variable "rds_instance_id" {
  type    = string
  default = ""
}

variable "notification_emails" {
  type    = list(string)
  default = []
}

variable "slack_webhook_url" {
  type      = string
  default   = ""
  sensitive = true
}
