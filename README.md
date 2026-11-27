# Link to Application Github repository
https://github.com/eugenewongyj/cloud-ntu-capstone-group2-app

# Reminder
1. to rerun the github oidc bootstrap if the permission is purged

# Pre-flash-sale checklist
For peak events (e.g. 11.11 at midnight, Black Friday). Day-to-day settings are kept small to save cost, so scale up **before** the sale and back down **after**.

## 1 week before
- [ ] **Load test** with `src/load-generator` (app repo) at the expected peak. Fix whatever slows down first.
- [ ] **Agree on the expected peak** (requests per second) and on the sale's start and end times.
- [ ] **Check the dashboards and alerts** (Grafana/Prometheus) cover cart, catalog, orders, DynamoDB throttling and Aurora CPU/ACU.

## 1–2 days before (changes take time to apply)
- [ ] **DynamoDB: pre-warm the carts table.** On-demand only absorbs about 2× the previous peak instantly, and the aws provider v5 has no Terraform setting for this, so run once (one-time charge):
  ```bash
  aws dynamodb update-table --table-name group2-capstone-carts \
    --warm-throughput ReadUnitsPerSecond=<peak reads/s>,WriteUnitsPerSecond=<peak writes/s>
  ```
- [ ] **Aurora: raise the ceiling.** `aurora_max_capacity` defaults to **1 ACU**, which is likely the first bottleneck. Raise it (e.g. 8–16) in `variables.tf`, and consider raising `aurora_min_capacity` so it doesn't start cold.
- [ ] **ElastiCache (checkout)**: confirm `checkout_cache_ecpu_max` and `checkout_cache_max_storage_gb` (cost caps in `elasticache.tf`) are above the expected peak, so the caps don't throttle the sale.
- [ ] **App pods:** raise replica counts / autoscaling limits for `ui`, `catalog`, `cart`, `checkout` and `orders` in `gitops/app/apps/*.yaml`.
- [ ] **Bootstrap permissions** are applied (`github-oidc-bootstrap`), so the pipeline doesn't fail mid-change.

## ~1 hour before the sale
- [ ] **ElastiCache (checkout): pre-warm.** Serverless scales automatically, but pre-warming means capacity is ready at the launch minute. Raise the minimum and apply through the pipeline:
  ```hcl
  checkout_cache_ecpu_min = <expected peak ECPU/s> # must be >= 1000; you pay for this minimum while it is set
  ```

## Sale day
- [ ] Freeze deployments (no merges to `main`) from a few hours before until after the sale.
- [ ] Have someone watching the dashboards at the start time.
- [ ] Watch for: DynamoDB `ThrottledRequests`, Aurora `ServerlessDatabaseCapacity` at its max, ElastiCache `ThrottledCmds` / `ElastiCacheProcessingUnits` near `checkout_cache_ecpu_max`, pod restarts.

## After the sale
- [ ] **Scale back down** to save cost: revert Aurora max ACU, pod replicas, set `checkout_cache_ecpu_min = 0` (ElastiCache).
- [ ] Note the actual peak numbers here for next time.

<!-- CAPSTONE-SRE-INTERACTIVE-START -->

## Interactive SRE assessment automation

The implementation extends the existing Capstone
GitOps and observability architecture.

- Normal Sale: five minutes at baseline traffic.
- 11:11 Flash Sale: five minutes with 10x and 20x stages.
- Recovery: five to ten minutes at baseline traffic.
- Application recovery target: within five minutes.
- Product listing p95 target: below 500 ms.
- HTTP and content failure targets: below 1%.
- Shared production target: retail-store via CloudFront.
- Shared Grafana controls and run-specific telemetry.
- Existing Prometheus, Alertmanager and Discord routing.
- Bounded recurrence and authenticated Start/Stop controls.

### Engineering traceability

- [Exact source-line map](gitops/sre/validate/docs/engineering-source-map.md)
- [Detailed code transitivity and Mermaid diagrams](gitops/sre/validate/docs/code-transitivity.md)

### Implementation status

Source implementation and local validation are distinct
from deployment readiness.

Signing, ECR publication, secure Helm provisioning,
Argo CD activation and shared runtime validation remain
pending. No production load or infrastructure mutation
is performed by the local validation script.

<!-- CAPSTONE-SRE-INTERACTIVE-END -->
