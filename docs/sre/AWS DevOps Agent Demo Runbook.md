# AWS DevOps Agent Investigation Demo Runbook

---

## Architecture Overview (Demo Reference)

```text
[Fault Injection in EKS (retail-store)]
        │
        ▼
[Prometheus Rule Fires (severity: critical)]
        │
        ▼
[Alertmanager (capstone-discord-routing)]
        ├──► [Discord Webhook] ──► SRE Alert Channel (critical | warning)
        └──► [Relay Lambda (group2-capstone-devops-agent-relay)]
                    │  (Signs payload with HMAC-SHA256 from Secrets Manager)
                    ▼
             [AWS DevOps Agent Space (group2-capstone-agent-space)]
                    │  (Inspects EKS pods/events, CloudWatch metrics/logs, AWS resources)
                    ▼
             [Automated Root-Cause Investigation & Remediation Plan]
```

---

## Pre-Demo Checklist (5 Minutes Before Demo)

Run these checks to confirm the cluster and alerting pipeline are healthy before injecting a fault:

```bash
# 1. Verify all retail-store pods are Running and Ready
kubectl get pods -n retail-store

# 2. Verify ArgoCD applications are Synced and Healthy
kubectl get applications -n argocd

# 3. Verify the Kubernetes secret points to the active relay Lambda Function URL
kubectl get secret devops-agent-webhook -n monitoring -o jsonpath='{.data.webhook-url}' | base64 -d; echo ""
# Expected: https://56gzkf6tzlqxx7ptdmhtd2oxte0eydcs.lambda-url.ap-southeast-1.on.aws/

# 4. Verify no lingering critical retail-store alerts are active
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
  amtool alert query --alertmanager.url=http://localhost:9093
```

---

## Step 1: Inject a Controlled Application Fault

Pause ArgoCD `automated` sync on the target application (`cart`) and root apps so ArgoCD does not immediately revert your demo fault, then deploy a non-existent container image to trigger `ImagePullBackOff` and `RetailStorePodNotReady` / `RetailStoreDeploymentUnavailable`.

```bash
# 1. Temporarily disable automated sync on root, root-app, and cart
for app in root root-app cart; do
  kubectl patch application "$app" -n argocd --type merge \
    -p '{"spec":{"syncPolicy":null}}'
done

# 2. Set an invalid image tag on the carts deployment
kubectl set image deployment/carts carts=public.ecr.aws/aws-containers/retail-store-sample-cart:broken-demo-test -n retail-store

# 3. Watch the new ReplicaSet pods enter ImagePullBackOff
kubectl get pods -n retail-store -l app.kubernetes.io/name=carts -w
```

*Expected Timing:*
* **0–30s:** New `carts` pods enter `ErrImagePull` / `ImagePullBackOff`.
* **~2m:** Prometheus rules `RetailStorePodNotReady` and `RetailStoreDeploymentUnavailable` evaluate to `firing` with `severity="critical"`.
* **~2m 15s:** Alertmanager dispatches to both Discord and `group2-capstone-devops-agent-relay`.

---

## Step 2: Live Demo Verification Walkthrough

Show the audience each stage of the automated incident response pipeline:

### A. Verify Alertmanager & Discord Notification
1. Open the **Discord SRE channel** to show the `[FIRING] RetailStorePodNotReady` and `[FIRING] RetailStoreDeploymentUnavailable` notifications.
2. Optionally confirm active alerts in Alertmanager:
   ```bash
   kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
     amtool alert query namespace=retail-store --alertmanager.url=http://localhost:9093
   ```

### B. Verify Relay Lambda Forwarding
Tail the relay Lambda logs to show the HMAC-signed payload succeeding with `HTTP 200` / `202`:
```bash
aws logs tail /aws/lambda/group2-capstone-devops-agent-relay --since 5m --region ap-southeast-1 --format short
```
*Look for:* `Forwarded RetailStorePodNotReady (firing) -> HTTP 200` (or `202`).

### C. Walk Through the AWS DevOps Agent Investigation
1. Open the **AWS DevOps Agent** console in `ap-southeast-1` and select **`group2-capstone-agent-space`** (or open the **Operator Web App**).
2. Click into the newly created **Investigation** for `RetailStorePodNotReady` / `RetailStoreDeploymentUnavailable`.
3. Highlight the autonomous triage steps performed by the agent:
   * Correlated the webhook metadata (`cluster: group2-capstone-eks`, `namespace: retail-store`, `deployment: carts`).
   * Queried Kubernetes pod/deployment status and events via its EKS access policy (`AmazonAIOpsAssistantPolicy`).
   * Identified `ImagePullBackOff` on image tag `broken-demo-test` as the root cause and generated a rollback recommendation.

---

## Step 3: Remediate & Restore Normal Operations

Demonstrate recovery by rolling back the `carts` deployment and re-enabling ArgoCD GitOps self-healing:

```bash
# 1. Roll back the carts deployment to the previous working ReplicaSet
kubectl rollout undo deployment/carts -n retail-store

# 2. Confirm all carts pods return to 1/1 Running
kubectl rollout status deployment/carts -n retail-store
kubectl get pods -n retail-store | grep -i cart

# 3. Re-enable ArgoCD automated sync with prune and selfHeal
for app in root root-app cart; do
  kubectl patch application "$app" -n argocd --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
done
```

### Post-Demo Verification
1. **ArgoCD:** Confirm `cart`, `root`, and `root-app` show `Synced` and `Healthy` (`kubectl get applications -n argocd`).
2. **Discord & DevOps Agent:** Within ~2 minutes, Alertmanager sends `[RESOLVED]` notifications to Discord and triggers the `action: "resolved"` update to the DevOps Agent relay.