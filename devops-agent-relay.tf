# =============================================================================
# AWS DevOps Agent Alertmanager Relay (Terraform)
# =============================================================================

resource "aws_iam_role" "devops_agent_webhook_relay" {
  name = "${var.project_name}-devops-agent-relay-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "devops_agent_relay_basic" {
  role       = aws_iam_role.devops_agent_webhook_relay.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "devops_agent_relay_secrets" {
  name = "${var.project_name}-devops-agent-relay-secrets"
  role = aws_iam_role.devops_agent_webhook_relay.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/sre/devops-agent-webhook-??????"
    }]
  })
}

data "archive_file" "devops_agent_relay_zip" {
  type        = "zip"
  output_path = "${path.module}/devops_agent_relay.zip"

  source {
    filename = "index.py"
    content  = <<-PY
      import base64
      import hashlib
      import hmac
      import json
      import os
      import urllib.error
      import urllib.request
      from datetime import datetime, timezone
      import boto3

      SECRET_ARN = os.environ["SECRET_ARN"]
      _cached_secret = None


      def get_secret():
          global _cached_secret
          if not _cached_secret:
              client = boto3.client("secretsmanager")
              resp = client.get_secret_value(SecretId=SECRET_ARN)
              _cached_secret = json.loads(resp["SecretString"])
          return _cached_secret


      def iso_timestamp_ms():
          now = datetime.now(timezone.utc)
          return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


      def handler(event, context):
          body_raw = event.get("body", "{}")
          if event.get("isBase64Encoded"):
              body_raw = base64.b64decode(body_raw).decode("utf-8")

          am = json.loads(body_raw)
          alerts = am.get("alerts", [])
          first = alerts[0] if alerts else {}
          labels = first.get("labels", {})
          annotations = first.get("annotations", {})

          status = am.get("status", "firing").lower()
          action = "resolved" if status == "resolved" else "created"
          alertname = labels.get("alertname", "PrometheusAlert")
          namespace = labels.get("namespace", "retail-store")
          pod = labels.get("pod", "N/A")
          deployment = labels.get("deployment", "N/A")
          incident_id = first.get("fingerprint", f"{namespace}-{alertname}")

          summary = annotations.get("summary", f"[{status.upper()}] {alertname} in {namespace}")
          detail_text = annotations.get("description", "No description provided.")

          # Embed full Kubernetes context inside description because DevOps Agent
          # uses title, description, priority, and incidentId for investigation context.
          rich_description = (
              f"{detail_text}\n\n"
              f"Cluster: group2-capstone-eks (ap-southeast-1)\n"
              f"Namespace: {namespace}\n"
              f"Alert: {alertname}\n"
              f"Deployment: {deployment}\n"
              f"Pod: {pod}\n"
              f"Status: {status.upper()}\n"
              f"Labels: {json.dumps(labels)}"
          )

          ts = iso_timestamp_ms()
          devops_payload = {
              "eventType": "incident",
              "incidentId": incident_id,
              "action": action,
              "priority": "CRITICAL",
              "title": summary,
              "description": rich_description,
              "timestamp": ts,
              "service": deployment if deployment != "N/A" else namespace,
              "data": {
                  "metadata": {
                      "cluster": "group2-capstone-eks",
                      "namespace": namespace,
                      "alertname": alertname,
                      "labels": labels,
                      "annotations": annotations,
                  }
              },
          }

          secret = get_secret()
          webhook_url = secret["webhook-url"]
          hmac_secret = secret["hmac-secret"].encode("utf-8")

          payload_str = json.dumps(devops_payload, separators=(",", ":"))
          sig_input = f"{ts}:{payload_str}".encode("utf-8")
          sig_b64 = base64.b64encode(
              hmac.new(hmac_secret, sig_input, hashlib.sha256).digest()
          ).decode("utf-8")

          req = urllib.request.Request(
              webhook_url,
              data=payload_str.encode("utf-8"),
              headers={
                  "Content-Type": "application/json",
                  "x-amzn-event-timestamp": ts,
                  "x-amzn-event-signature": sig_b64,
              },
              method="POST",
          )

          try:
              with urllib.request.urlopen(req, timeout=10) as resp:
                  resp_body = resp.read().decode("utf-8")
                  print(f"Forwarded {alertname} ({status}) -> HTTP {resp.status}: {resp_body}")
                  return {"statusCode": resp.status, "body": resp_body}
          except urllib.error.HTTPError as err:
              err_body = err.read().decode("utf-8")
              print(f"DevOps Agent HTTP {err.code}: {err_body}")
              return {"statusCode": err.code, "body": err_body}
    PY
  }
}

resource "aws_lambda_function" "devops_agent_relay" {
  function_name    = "${var.project_name}-devops-agent-relay"
  role             = aws_iam_role.devops_agent_webhook_relay.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  timeout          = 15
  filename         = data.archive_file.devops_agent_relay_zip.output_path
  source_code_hash = data.archive_file.devops_agent_relay_zip.output_base64sha256

  environment {
    variables = {
      SECRET_ARN = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/sre/devops-agent-webhook"
    }
  }
}

resource "aws_lambda_function_url" "devops_agent_relay" {
  function_name      = aws_lambda_function.devops_agent_relay.function_name
  authorization_type = "NONE"
}

output "devops_agent_relay_url" {
  description = "Function URL for Alertmanager to forward critical alerts to AWS DevOps Agent"
  value       = aws_lambda_function_url.devops_agent_relay.function_url
}

resource "aws_lambda_permission" "devops_agent_relay_invoke" {
  statement_id  = "FunctionURLAllowInvokeAction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.devops_agent_relay.function_name
  principal     = "*"
}