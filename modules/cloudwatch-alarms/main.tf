# =============================================================================
# CloudWatch Alarms Module
# =============================================================================
# Creates CloudWatch alarms for EC2, ECS, and RDS health monitoring.
# Alarms trigger SNS notifications and optionally invoke Lambda remediation.
# =============================================================================

# -----------------------------------------------------------------------------
# EC2 Instance Health Alarms
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ec2_status_check" {
  for_each = toset(var.ec2_instance_ids)

  alarm_name          = "${var.environment}-ec2-status-check-${each.value}"
  alarm_description   = "EC2 instance ${each.value} failed status check - auto-remediation enabled"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = compact([
    var.sns_topic_arn,
    var.ec2_lambda_arn != "" ? var.ec2_lambda_arn : "",
  ])

  ok_actions = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name     = "${var.environment}-ec2-status-check-${each.value}"
    Instance = each.value
  })
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu_high" {
  for_each = toset(var.ec2_instance_ids)

  alarm_name          = "${var.environment}-ec2-cpu-high-${each.value}"
  alarm_description   = "EC2 instance ${each.value} CPU utilization exceeds 90%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 90

  dimensions = {
    InstanceId = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name     = "${var.environment}-ec2-cpu-high-${each.value}"
    Instance = each.value
  })
}

# -----------------------------------------------------------------------------
# ECS Service Health Alarms
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  count = var.ecs_cluster_name != "" && var.ecs_service_name != "" ? 1 : 0

  alarm_name          = "${var.environment}-ecs-running-tasks-low"
  alarm_description   = "ECS service ${var.ecs_service_name} running task count dropped below desired"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 1

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = compact([
    var.sns_topic_arn,
    var.ecs_lambda_arn,
  ])

  ok_actions = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name    = "${var.environment}-ecs-running-tasks-low"
    Cluster = var.ecs_cluster_name
    Service = var.ecs_service_name
  })
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_utilization" {
  count = var.ecs_cluster_name != "" && var.ecs_service_name != "" ? 1 : 0

  alarm_name          = "${var.environment}-ecs-cpu-high"
  alarm_description   = "ECS service ${var.ecs_service_name} CPU utilization exceeds 85%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 85

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name = "${var.environment}-ecs-cpu-high"
  })
}

# -----------------------------------------------------------------------------
# RDS Health Alarms
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.rds_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-rds-cpu-high"
  alarm_description   = "RDS instance ${var.rds_instance_id} CPU exceeds 90%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 90

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name = "${var.environment}-rds-cpu-high"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  count = var.rds_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-rds-storage-low"
  alarm_description   = "RDS instance ${var.rds_instance_id} free storage below 5GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5 GB in bytes

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name = "${var.environment}-rds-storage-low"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  count = var.rds_instance_id != "" ? 1 : 0

  alarm_name          = "${var.environment}-rds-connections-high"
  alarm_description   = "RDS instance ${var.rds_instance_id} connections exceed threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 100

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = [var.sns_topic_arn]

  tags = merge(var.tags, {
    Name = "${var.environment}-rds-connections-high"
  })
}
