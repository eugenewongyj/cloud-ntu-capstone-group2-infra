# ADR 0004: Store Catalog and Orders data in Amazon Aurora Serverless v2 (MySQL for Catalog, PostgreSQL for Orders) in ap-southeast-1

- **Status:** Accepted
- **Date:** 2026-11-28
- **Deciders:** Capstone Group 2 (1 Solutions Architect, 2 DevSecOps, 2 SRE)
- **Author:** [Your name] (Solutions Architect)
- **Related:** ADR 0001 (compute platform), APP-ADR-004 in ADR 0003 (one data store per microservice)

## Context

Two of SwiftKart's five microservices need a **relational database** (tables with
rows, columns and transactions):

- **Catalog:** the product list shoppers browse. It is read very often and changes
  rarely. It is on the path of our latency target: **p95 ≤ 500 ms on product listing**.
- **Orders:** the permanent record of every order placed. It involves money, so it
  must never be lost and must stay accurate.

(Carts use DynamoDB and checkout uses ElastiCache Valkey. Those choices are covered
separately; this ADR covers relational data only.)

These constraints shaped the decision:

- **The app decides the database engine:** the sample app's Catalog service supports
  **MySQL**, and its Orders service supports **PostgreSQL**. Choosing a different
  engine would mean rewriting application code, which is outside our scope.
- **Traffic pattern:** mostly low, steady traffic, with a **10–20× spike** during a
  flash sale. The database must handle the spike without being sized for it all month.
- **Cost accountability (hard constraint):** an idle day must be cheap, and the extra
  cost of a sale must be small and explainable.
- **Small team, short timeline:** we cannot spend time patching servers, taking
  backups by hand or managing failover.
- **Security and compliance:** data must stay in **ap-southeast-1 (Singapore)**,
  be encrypted, be unreachable from the internet, and use no hard-coded passwords.
- **Tooling:** everything must be defined in **Terraform** and deployed through
  **GitHub Actions**.

## Options considered

### Option 1: Run MySQL and PostgreSQL as pods inside the EKS cluster

**Pros**
- No extra AWS database fee; the databases use the worker nodes we already pay for.
- The sample app's Helm charts can deploy them this way out of the box.

**Cons**
- We would own backups, upgrades, storage, replication and failover ourselves.
- If a node or Availability Zone fails, the database can go down with it, and
  recovery is manual.
- Databases compete with the shop for node capacity during the flash sale, which
  is exactly when the shop needs it most.
- Hard to defend for order data that involves money.

### Option 2: Amazon RDS with fixed-size instances (RDS for MySQL / RDS for PostgreSQL)

**Pros**
- Fully managed: AWS handles backups, patching and Multi-AZ failover.
- Simple, predictable monthly price for a given instance size.
- Same engines the app needs; no code changes.

**Cons**
- **Fixed size:** we must pick an instance large enough for the 11.11 peak and pay
  for that size every hour of the month, even on an idle Tuesday.
- Resizing for a sale means a planned change and a short outage, and someone has to
  remember to do it before and undo it after.
- Works against our cost accountability constraint.

### Option 3: Amazon Aurora Serverless v2, MySQL for Catalog and PostgreSQL for Orders (chosen)

**Pros**
- **Scales automatically** in small steps (Aurora Capacity Units, ACUs) within
  seconds, while running, with no outage. It grows for the sale and shrinks after it.
- **Billed per second** for the capacity actually used, so the sale's extra database
  cost is small (about **$1.20** for a 2-hour sale in our cost model).
- Fully managed: automated backups, patching, encryption, and storage that is
  copied across 3 Availability Zones by Aurora itself.
- Same MySQL and PostgreSQL engines the app already supports; no code changes.
- Catalog runs a **writer plus a reader in different AZs**, so it survives an AZ
  outage by failing over to the reader.

**Cons**
- Never fully free: each instance keeps a minimum of **0.5 ACU** running all the
  time (about **$58 per instance per month** at our estimated $0.16 per ACU-hour).
  Our 4 instances add up to about **$234 a month** at minimum.
- The cost per unit of capacity is higher than a fixed RDS instance, so it only
  saves money when traffic is spiky. For SwiftKart, it is.
- Two different engines mean two sets of settings, logs and alarms to look after.

### Option 4 (briefly considered): Move Catalog and Orders to DynamoDB

**Pros**
- Pay-per-request with no minimum, like the carts table.

**Cons**
- The app's Catalog and Orders services are written for SQL databases; we would
  have to rewrite them.
- Rejected early.

## Decision

We will store **Catalog** data in **Aurora MySQL Serverless v2** and **Orders** data
in **Aurora PostgreSQL Serverless v2**, in **ap-southeast-1**, provisioned with
**Terraform** (`aurora-mysql.tf`, `aurora-postgres.tf`, `staging-orders-checkout.tf`).

As deployed:

| Cluster | Used by | Instances | Capacity range | Notes |
| --- | --- | --- | --- | --- |
| `group2-capstone-aurora-mysql` | Catalog (production) | 2 (writer + reader, pinned to different AZs) | 0.5–1 ACU each | Error and slow-query logs to CloudWatch |
| `group2-capstone-orders-pg` | Orders (production) | 1 (writer) | 0.5–2 ACU | PostgreSQL logs to CloudWatch |
| `group2-capstone-orders-pg-staging` | Orders (staging) | 1 (writer) | 0.5–1 ACU | Smaller cap than production to save cost |

Staging Catalog currently uses the app's in-memory store instead of Aurora.

Security settings on all clusters:
- Placed in the **isolated database subnets**; `publicly_accessible = false`.
- Security groups allow connections **only from the EKS cluster security group**,
  not from the whole VPC.
- **Encrypted at rest** (`storage_encrypted = true`).
- **No hard-coded passwords:** AWS generates and stores the master password in
  Secrets Manager (`manage_master_user_password = true`). External Secrets copies it
  into Kubernetes, with read access to that one secret only.

**Why:**
1. **Flash-sale elasticity:** capacity grows and shrinks automatically during the
   sale, with no resizing and no outage.
2. **Cost accountability:** we pay a small always-on minimum on an idle day, and the
   sale adds only about $1.20 of database cost because extra capacity is billed per
   second and switches off afterwards.
3. **No code changes:** the engines match what the sample app already supports.
4. **Less to manage:** backups, patching, encryption and storage replication are
   handled by AWS, which suits a 5-person team.

We accept the always-on minimum and the higher price per unit of capacity because
SwiftKart's traffic is spiky, and paying per second for the spike is cheaper than
paying for peak size all month.

## Consequences

### What this makes easier
- Surviving the flash sale without anyone resizing databases before or after.
- Explaining database cost: a fixed minimum plus a small per-second charge for the spike.
- Keeping each service's data separate (Catalog and Orders each own a cluster),
  in line with APP-ADR-004.
- Meeting security requirements: private subnets, encryption, no stored passwords,
  and access only from the cluster.
- Troubleshooting with database logs in CloudWatch, and CPU alarms on both
  production clusters (threshold 80%).

### What this rules out / makes harder
- **Rules out** a database that costs nothing when idle: we pay about $234 a month
  minimum across 4 instances even with no traffic.
- **Orders has no standby instance.** If its single writer fails, Aurora must start
  a replacement, which takes several minutes. During that time customers can browse
  but cannot place orders. Data is not lost, because storage is replicated across
  3 AZs.
- **Catalog's reader is a standby only.** The Catalog app connects to the cluster
  (writer) endpoint, so the reader takes over on failure but does not share the
  read load.
- **Capacity caps limit the biggest spikes.** Catalog is capped at 1 ACU per
  instance. At about 30× normal traffic, this cap is one of the first limits we hit.
- **Capstone-only safety settings:** backups are kept for **1 day**, deletion
  protection is **off**, and no final snapshot is taken on delete. These make
  tear-down easy for the course but are not suitable for a real shop.

### Follow-up actions
- Before a real launch: raise backup retention (e.g. 7–35 days), turn on deletion
  protection, and take a final snapshot on delete.
- Add a reader instance to the Orders cluster so it can fail over in about a minute
  instead of several minutes.
- Point Catalog's read traffic at the reader endpoint so both instances share the load.
- Load-test at 20–30× and raise `aurora_max_capacity` if Catalog CPU or latency
  shows the 1 ACU cap is reached.
- Confirm the Singapore Aurora Serverless v2 price per ACU-hour (our model uses an
  estimated $0.16) and update the cost estimate.
