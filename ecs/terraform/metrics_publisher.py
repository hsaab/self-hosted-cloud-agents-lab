import base64
import json
import os
import urllib.error
import urllib.request

import boto3


cloudwatch = boto3.client("cloudwatch")
secretsmanager = boto3.client("secretsmanager")


def handler(event, context):
    api_key = _read_secret(os.environ["CURSOR_API_KEY_SECRET_ARN"])
    summary = _fetch_summary(os.environ["CURSOR_FLEET_SUMMARY_URL"], api_key)

    fleet = summary.get("teamSummary") or summary.get("userSummary") or {}
    connected = int(fleet.get("totalConnected") or fleet.get("connected") or 0)
    in_use = int(fleet.get("inUse") or fleet.get("in_use") or 0)
    idle = max(connected - in_use, 0)
    utilization_percent = (in_use / connected * 100) if connected else 0.0

    dimensions = [
        {"Name": name, "Value": value}
        for name, value in json.loads(os.environ["METRIC_DIMENSIONS"]).items()
    ]

    cloudwatch.put_metric_data(
        Namespace=os.environ["METRICS_NAMESPACE"],
        MetricData=[
            _metric("Connected", connected, "Count", dimensions),
            _metric("InUse", in_use, "Count", dimensions),
            _metric("Idle", idle, "Count", dimensions),
            _metric("UtilizationPercent", utilization_percent, "Percent", dimensions),
        ],
    )

    return {
        "connected": connected,
        "inUse": in_use,
        "idle": idle,
        "utilizationPercent": utilization_percent,
    }


def _read_secret(secret_arn):
    response = secretsmanager.get_secret_value(SecretId=secret_arn)
    if "SecretString" in response:
        return response["SecretString"]

    return base64.b64decode(response["SecretBinary"]).decode("utf-8")


def _fetch_summary(url, api_key):
    auth_value = base64.b64encode(f"{api_key}:".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Basic {auth_value}",
            "Accept": "application/json",
            "User-Agent": "cursor-ecs-metrics-publisher/1.0",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Cursor fleet summary request failed: {error.code} {body}") from error


def _metric(name, value, unit, dimensions):
    return {
        "MetricName": name,
        "Value": value,
        "Unit": unit,
        "Dimensions": dimensions,
    }
