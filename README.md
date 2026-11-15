# Link to Application Github repository
https://github.com/eugenewongyj/cloud-ntu-capstone-group2-app

# Reminder
1. to rerun the github oidc bootstrap if the permission is purged

# Pre-flash-sale checklist
For peak events (e.g. 11.11 at midnight, Black Friday). Day-to-day settings are kept small to save cost, so scale up **before** the sale and back down **after**.

> [!IMPORTANT]
> **OpenSearch (catalog search) minimum OCU: the sale rule**
>
> | When | `opensearch_search_ocu_min` | `opensearch_index_ocu_min` | Why |
> |---|---|---|---|
> | **BEFORE a sale** (1–2 days ahead) | **2** | **2** | Search is already running at launch. At 0, the first searches are slow while it starts up |
> | **AFTER a sale** | **0** | **0** | No compute cost when idle. Leaving it at 2 costs roughly US$700+/month |
>
> Change both values in `variables.tf`, open a PR, merge it, then run the **Terraform CD** workflow.

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
- [ ] **OpenSearch Serverless: pre-warm.** Staging minimums are **0** (no compute cost when idle, but the first search after a quiet period is slow). In `variables.tf`, raise them so search is ready at launch, and confirm the maximums are high enough (allowed values: 0, 2, 4, 8, 16 or multiples of 16):
  ```hcl
  opensearch_search_ocu_min = 2  # staging 0
  opensearch_index_ocu_min  = 2  # staging 0
  opensearch_search_ocu_max = 32 # raise to 48/64 if the load test needs it
  ```
  Also confirm `opensearch_standby_replicas = "ENABLED"`.
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
- [ ] Watch for: DynamoDB `ThrottledRequests`, DAX `CPUUtilization`, Aurora `ServerlessDatabaseCapacity` at its max, ElastiCache `ThrottledCmds` / `ElastiCacheProcessingUnits` near `checkout_cache_ecpu_max`, pod restarts.

## After the sale
- [ ] **Scale back down** to save cost: revert DAX (`dax.t3.small`, 1 node), Aurora max ACU, pod replicas, set `checkout_cache_ecpu_min = 0` (ElastiCache), and set the OpenSearch minimums back to 0 (`opensearch_search_ocu_min`, `opensearch_index_ocu_min`).
- [ ] Note the actual peak numbers here for next time.