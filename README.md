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
- [ ] **DAX: scale up** in `dynamodb-dax.tf` (or with `-var`), then apply through the pipeline:
  ```hcl
  dax_node_type  = "dax.r5.large" # not burstable: dax.t3.* slows down once CPU credits run out
  dax_node_count = 3              # one per AZ: survives a node failure
  ```
  Changing the node type **rebuilds the cluster**, so do it well ahead of the sale.
- [ ] **DynamoDB: pre-warm the carts table.** On-demand only absorbs about 2× the previous peak instantly, and the aws provider v5 has no Terraform setting for this, so run once (one-time charge):
  ```bash
  aws dynamodb update-table --table-name group2-capstone-carts \
    --warm-throughput ReadUnitsPerSecond=<peak reads/s>,WriteUnitsPerSecond=<peak writes/s>
  ```
- [ ] **Aurora: raise the ceiling.** `aurora_max_capacity` defaults to **1 ACU**, which is likely the first bottleneck. Raise it (e.g. 8–16) in `variables.tf`, and consider raising `aurora_min_capacity` so it doesn't start cold.
- [ ] **OpenSearch Serverless** (if deployed): confirm `opensearch_search_ocu_max` is high enough and `opensearch_standby_replicas = "ENABLED"`.
- [ ] **App pods:** raise replica counts / autoscaling limits for `ui`, `catalog`, `cart`, `checkout` and `orders` in `gitops/app/apps/*.yaml`.
- [ ] **Bootstrap permissions** are applied (`github-oidc-bootstrap`), so the pipeline doesn't fail mid-change.

## Sale day
- [ ] Freeze deployments (no merges to `main`) from a few hours before until after the sale.
- [ ] Have someone watching the dashboards at the start time.
- [ ] Watch for: DynamoDB `ThrottledRequests`, DAX `CPUUtilization`, Aurora `ServerlessDatabaseCapacity` at its max, pod restarts.

## After the sale
- [ ] **Scale back down** to save cost: revert DAX (`dax.t3.small`, 1 node), Aurora max ACU and pod replicas.
- [ ] Note the actual peak numbers here for next time.