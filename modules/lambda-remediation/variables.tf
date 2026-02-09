variable "environment" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "enable_ec2_restart" {
  type    = bool
  default = true
}

variable "enable_ecs_scale" {
  type    = bool
  default = true
}

variable "enable_sg_remediate" {
  type    = bool
  default = true
}

variable "enable_rds_recover" {
  type    = bool
  default = true
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

variable "tags" {
  type    = map(string)
  default = {}
}
