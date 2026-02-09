output "alarm_arns" {
  description = "Map of all CloudWatch alarm ARNs"
  value = merge(
    { for k, v in aws_cloudwatch_metric_alarm.ec2_status_check : "ec2-status-${k}" => v.arn },
    { for k, v in aws_cloudwatch_metric_alarm.ec2_cpu_high : "ec2-cpu-${k}" => v.arn },
    { for v in aws_cloudwatch_metric_alarm.ecs_running_tasks : "ecs-tasks" => v.arn },
    { for v in aws_cloudwatch_metric_alarm.ecs_cpu_utilization : "ecs-cpu" => v.arn },
    { for v in aws_cloudwatch_metric_alarm.rds_cpu_high : "rds-cpu" => v.arn },
    { for v in aws_cloudwatch_metric_alarm.rds_free_storage : "rds-storage" => v.arn },
  )
}
