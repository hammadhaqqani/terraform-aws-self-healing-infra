"""
ECS Auto-Scale Lambda
=====================
Forces a new ECS deployment when running task count drops below desired.
Triggered by CloudWatch alarms monitoring ECS RunningTaskCount.

Flow:
  1. Receive alarm notification
  2. Describe the ECS service to confirm the issue
  3. Force a new deployment to reschedule tasks
  4. Notify via SNS
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs = boto3.client("ecs")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown")
CLUSTER_NAME = os.environ.get("CLUSTER_NAME", "")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "")


def lambda_handler(event, context):
    """Main handler for ECS auto-scale remediation."""
    logger.info("Received event: %s", json.dumps(event))

    cluster = CLUSTER_NAME
    service = SERVICE_NAME

    # Try to extract from alarm event if not in env vars
    if not cluster or not service:
        cluster, service = extract_from_event(event)

    if not cluster or not service:
        logger.error("Could not determine ECS cluster/service")
        return {"statusCode": 400, "body": "Missing cluster or service info"}

    return remediate_service(cluster, service)


def extract_from_event(event):
    """Extract cluster and service from CloudWatch alarm dimensions."""
    cluster, service = "", ""
    for record in event.get("Records", []):
        try:
            message = json.loads(record.get("Sns", {}).get("Message", "{}"))
            dimensions = message.get("Trigger", {}).get("Dimensions", [])
            for dim in dimensions:
                if dim.get("name") == "ClusterName":
                    cluster = dim["value"]
                elif dim.get("name") == "ServiceName":
                    service = dim["value"]
        except (json.JSONDecodeError, KeyError):
            pass
    return cluster, service


def remediate_service(cluster, service):
    """Force a new deployment on the ECS service."""
    try:
        # Describe current state
        response = ecs.describe_services(cluster=cluster, services=[service])
        services = response.get("services", [])

        if not services:
            msg = f"Service {service} not found in cluster {cluster}"
            logger.error(msg)
            return {"statusCode": 404, "body": msg}

        svc = services[0]
        desired = svc.get("desiredCount", 0)
        running = svc.get("runningCount", 0)
        status = svc.get("status", "UNKNOWN")

        logger.info(
            "Service %s: status=%s, desired=%d, running=%d",
            service, status, desired, running,
        )

        if running >= desired:
            msg = f"Service {service} running count ({running}) meets desired ({desired}). No action needed."
            logger.info(msg)
            return {"statusCode": 200, "body": msg}

        # Force new deployment
        logger.info("Forcing new deployment for %s/%s", cluster, service)
        ecs.update_service(
            cluster=cluster,
            service=service,
            forceNewDeployment=True,
        )

        msg = (
            f"Forced new deployment for {service} in {cluster}. "
            f"Running: {running}, Desired: {desired}"
        )
        logger.info(msg)
        send_notification(cluster, service, "FORCE_DEPLOYMENT", msg, running, desired)

        return {"statusCode": 200, "body": msg}

    except ClientError as e:
        error_msg = f"Failed to remediate ECS service {service}: {e}"
        logger.error(error_msg)
        send_notification(cluster, service, "REMEDIATION_FAILED", error_msg, 0, 0)
        return {"statusCode": 500, "body": error_msg}


def send_notification(cluster, service, action, message, running, desired):
    """Send remediation notification via SNS."""
    if not SNS_TOPIC_ARN:
        return
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{ENVIRONMENT.upper()}] ECS Auto-Heal: {action} - {service}",
            Message=json.dumps(
                {
                    "environment": ENVIRONMENT,
                    "cluster": cluster,
                    "service": service,
                    "action": action,
                    "running_count": running,
                    "desired_count": desired,
                    "message": message,
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                indent=2,
            ),
        )
    except ClientError as e:
        logger.error("Failed to send SNS notification: %s", e)
