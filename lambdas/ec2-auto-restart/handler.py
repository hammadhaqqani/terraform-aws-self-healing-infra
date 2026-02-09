"""
EC2 Auto-Restart Lambda
=======================
Automatically restarts EC2 instances that fail status checks.
Triggered by CloudWatch alarms via SNS.

Flow:
  1. Receive CloudWatch alarm notification
  2. Extract instance ID from alarm dimensions
  3. Check current instance state
  4. Attempt restart (stop + start for EBS-backed, reboot otherwise)
  5. Notify via SNS with remediation result
"""

import json
import logging
import os
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
sns = boto3.client("sns")

SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown")
MAX_RESTART_ATTEMPTS = 3
WAIT_BETWEEN_ATTEMPTS = 10


def lambda_handler(event, context):
    """Main handler for EC2 auto-restart."""
    logger.info("Received event: %s", json.dumps(event))

    instance_ids = extract_instance_ids(event)
    if not instance_ids:
        logger.warning("No instance IDs found in event")
        return {"statusCode": 200, "body": "No instances to process"}

    results = []
    for instance_id in instance_ids:
        result = remediate_instance(instance_id)
        results.append(result)

    return {"statusCode": 200, "body": json.dumps(results)}


def extract_instance_ids(event):
    """Extract EC2 instance IDs from CloudWatch alarm SNS event."""
    instance_ids = []

    for record in event.get("Records", []):
        try:
            message = json.loads(record.get("Sns", {}).get("Message", "{}"))
            trigger = message.get("Trigger", {})
            dimensions = trigger.get("Dimensions", [])
            for dim in dimensions:
                if dim.get("name") == "InstanceId":
                    instance_ids.append(dim["value"])
        except (json.JSONDecodeError, KeyError) as e:
            logger.error("Failed to parse SNS message: %s", e)

    # Fallback: check environment variable for configured instances
    if not instance_ids:
        configured = os.environ.get("INSTANCE_IDS", "")
        if configured:
            instance_ids = [i.strip() for i in configured.split(",") if i.strip()]

    return list(set(instance_ids))


def remediate_instance(instance_id):
    """Attempt to restart a failed EC2 instance."""
    logger.info("Remediating instance: %s", instance_id)

    try:
        # Get current instance state
        response = ec2.describe_instances(InstanceIds=[instance_id])
        reservations = response.get("Reservations", [])
        if not reservations or not reservations[0].get("Instances"):
            return {
                "instance_id": instance_id,
                "status": "error",
                "message": "Instance not found",
            }

        instance = reservations[0]["Instances"][0]
        state = instance["State"]["Name"]
        instance_name = get_instance_name(instance)

        logger.info(
            "Instance %s (%s) current state: %s", instance_id, instance_name, state
        )

        if state == "running":
            # Instance is running but failing checks -- reboot it
            return reboot_instance(instance_id, instance_name)
        elif state == "stopped":
            # Instance is stopped -- start it
            return start_instance(instance_id, instance_name)
        elif state in ("stopping", "pending"):
            # Instance is transitioning -- wait and retry
            logger.info("Instance %s is in '%s' state, waiting...", instance_id, state)
            time.sleep(WAIT_BETWEEN_ATTEMPTS)
            return remediate_instance(instance_id)
        else:
            msg = f"Instance {instance_id} in unrecoverable state: {state}"
            logger.warning(msg)
            send_notification(
                instance_id, instance_name, "MANUAL_INTERVENTION_NEEDED", msg
            )
            return {"instance_id": instance_id, "status": "manual", "message": msg}

    except ClientError as e:
        error_msg = f"AWS error remediating {instance_id}: {e}"
        logger.error(error_msg)
        return {"instance_id": instance_id, "status": "error", "message": error_msg}


def reboot_instance(instance_id, instance_name):
    """Reboot a running instance that's failing health checks."""
    logger.info("Rebooting instance %s", instance_id)
    ec2.reboot_instances(InstanceIds=[instance_id])
    msg = f"Successfully rebooted instance {instance_id} ({instance_name})"
    logger.info(msg)
    send_notification(instance_id, instance_name, "REBOOTED", msg)
    return {"instance_id": instance_id, "status": "rebooted", "message": msg}


def start_instance(instance_id, instance_name):
    """Start a stopped instance."""
    logger.info("Starting instance %s", instance_id)
    ec2.start_instances(InstanceIds=[instance_id])

    # Wait for running state
    waiter = ec2.get_waiter("instance_running")
    try:
        waiter.wait(
            InstanceIds=[instance_id], WaiterConfig={"Delay": 5, "MaxAttempts": 12}
        )
        msg = f"Successfully started instance {instance_id} ({instance_name})"
        logger.info(msg)
        send_notification(instance_id, instance_name, "STARTED", msg)
        return {"instance_id": instance_id, "status": "started", "message": msg}
    except Exception as e:
        msg = f"Timeout waiting for instance {instance_id} to start: {e}"
        logger.error(msg)
        send_notification(instance_id, instance_name, "START_TIMEOUT", msg)
        return {"instance_id": instance_id, "status": "timeout", "message": msg}


def get_instance_name(instance):
    """Extract Name tag from instance."""
    for tag in instance.get("Tags", []):
        if tag["Key"] == "Name":
            return tag["Value"]
    return "unnamed"


def send_notification(instance_id, instance_name, action, message):
    """Send remediation notification via SNS."""
    if not SNS_TOPIC_ARN:
        return

    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{ENVIRONMENT.upper()}] EC2 Auto-Heal: {action} - {instance_id}",
            Message=json.dumps(
                {
                    "environment": ENVIRONMENT,
                    "instance_id": instance_id,
                    "instance_name": instance_name,
                    "action": action,
                    "message": message,
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                },
                indent=2,
            ),
        )
    except ClientError as e:
        logger.error("Failed to send SNS notification: %s", e)
