# Architecture Decision Records (ADRs) — CI/CD, Ingress & Data Services

**Project:** `group2-capstone` (`ap-southeast-1`)

**Scope:** GitHub Actions CI/CD, OIDC Authentication, ECR Image Lifecycle, Ingress & TLS Automation, and Microservice Data Persistence

**Date:** November 2026

## Summary Index

| ADR ID | Title | Status | Key Components |
| :--- | :--- | :--- | :--- |
| **APP-ADR-001** | Authenticate GitHub Actions to AWS via Passwordless IAM OIDC Federation | Accepted | GitHub Actions, AWS IAM OIDC Provider, Scoped Deployment Roles |
| **APP-ADR-002** | Separate CI Build/Push Workflows from CD GitOps Manifest Synchronization | Accepted | GitHub Actions, Amazon ECR, GitOps Manifest Repo, ArgoCD |
| **APP-ADR-003** | Standardize Edge Routing & Automated TLS via Ingress Controller & `cert-manager` | Accepted | AWS Load Balancer Controller / NGINX Ingress, `cert-manager`, Let's Encrypt |
| **APP-ADR-004** | Decouple Microservice State into Managed & Scoped Data Stores (`retail-store`) | Accepted | `carts` (DynamoDB/In-Memory), `orders` (PostgreSQL/RDS), `catalog` (MySQL/RDS), `checkout` (Redis) |
| **APP-ADR-005** | Enforce Immutable Container Image Tagging & Automated ECR Lifecycle Policies | Accepted | Amazon ECR, Git SHA Tagging, ECR Lifecycle Rules |

---

## APP-ADR-001: Authenticate GitHub Actions to AWS via Passwordless IAM OIDC Federation

### Context
CI/CD pipelines running in GitHub Actions require AWS permissions to run `terraform plan`/`terraform apply`, push container images to Amazon ECR, and validate EKS deployments. Storing long-lived `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets in GitHub creates credential-leak and manual rotation risks.

### Decision
Provision an AWS IAM OpenID Connect (OIDC) identity provider in Terraform trusting `token.actions.githubusercontent.com`, and configure short-lived assumable IAM roles restricted by `sub` (repository/branch/environment) and `aud` conditions.

### Consequences
* **Positive:** Zero static AWS IAM user keys stored in GitHub; credentials expire automatically after each workflow job; CloudTrail logs attribute every API call to the exact GitHub repository and workflow run.
* **Negative:** Requires explicit IAM trust policy updates when adding new repositories, branches, or GitHub Environments.

---

## APP-ADR-002: Separate CI Build/Push Workflows from CD GitOps Manifest Synchronization

### Context
Allowing CI build pipelines to run `kubectl apply` directly against EKS bypasses GitOps auditability, complicates rollbacks, and grants CI runners direct cluster-admin credentials.

### Decision
Split delivery into two distinct stages:
1. **Continuous Integration (GitHub Actions):** Lint, test, build container images (or run Terraform infrastructure plans/applies), and push versioned images to Amazon ECR.
2. **Continuous Delivery (ArgoCD):** Update image tags or Helm values in the GitOps configuration repository so ArgoCD reconciles `retail-store` and `retail-staging` declaratively.

### Consequences
* **Positive:** Full Git commit history for every production deployment; instant rollbacks via `git revert` or `kubectl rollout undo`; CI runners do not require direct Kubernetes API write credentials.
* **Negative:** End-to-end deployment latency includes Git commit propagation and ArgoCD polling/webhook sync intervals.

---

## APP-ADR-003: Standardize Edge Routing & Automated TLS via Ingress Controller & `cert-manager`

### Context
Exposing internal dashboards (Grafana, ArgoCD) and storefront web endpoints (`ui`) individually via separate Classic Load Balancers increases AWS cost, fragments DNS management, and complicates TLS certificate renewal.

### Decision
Consolidate external HTTP/HTTPS traffic behind a shared Kubernetes Ingress layer backed by AWS Load Balancer Controller / Ingress Controller on public subnets, paired with `cert-manager` (`ClusterIssuer`) for automated TLS certificate issuance and renewal, and Kubernetes Secrets for basic/OIDC auth protection.

### Consequences
* **Positive:** Automated TLS lifecycle management without manual certificate renewals; centralized host/path routing across `retail-store`, `monitoring`, and `argocd`; reduced load balancer sprawl.
* **Negative:** Misconfigured Ingress annotations or `ClusterIssuer` rate limits can affect external reachability across multiple services simultaneously.

---

## APP-ADR-004: Decouple Microservice State into Managed & Scoped Data Stores (`retail-store`)

### Context
The `retail-store` sample architecture consists of polyglot microservices (`ui`, `catalog`, `carts`, `orders`, `checkout`) with distinct persistence patterns—relational transactional data, low-latency session/cart key-value lookups, and ephemeral checkout caching.

### Decision
Keep application pods stateless and bind each microservice to a purpose-built backing store injected via Kubernetes ConfigMaps and Secrets:
* **`carts`:** Key-value cart persistence (Amazon DynamoDB / local backend in non-prod) accessed via IRSA / scoped credentials.
* **`orders` & `catalog`:** Relational persistence (PostgreSQL / MySQL) isolated per service boundary.
* **`checkout`:** In-memory Redis store for transient checkout state.

### Consequences
* **Positive:** Pods can scale horizontally, restart, or roll back (`kubectl rollout undo`) without losing shopping cart or order state; clear service-level data ownership.
* **Negative:** Requires managing per-service connection strings, credentials in Secrets Manager, and network security group rules between EKS worker subnets and backing data stores.

---

## APP-ADR-005: Enforce Immutable Container Image Tagging & Automated ECR Lifecycle Policies

### Context
Deploying mutable tags such as `:latest` makes it impossible to verify which code revision is running in `retail-store`, breaks deterministic rollbacks, and causes Kubernetes `imagePullPolicy` caching inconsistencies.

### Decision
1. **Immutable Commit-SHA / SemVer Tags:** Tag container builds in Amazon ECR with immutable Git commit SHAs (and release tags) and configure ECR repositories with `image_tag_mutability = "IMMUTABLE"`.
2. **ECR Lifecycle Policies:** Apply Terraform-managed ECR lifecycle rules to automatically expire untagged images and retain only the most recent $N$ tagged releases per repository.

### Consequences
* **Positive:** Guarantees exact build traceability from running pod image tag back to Git commit; prevents accidental tag overwrites; controls ECR storage costs automatically.
* **Negative:** Re-running a build for the same commit requires a new commit or unique build suffix rather than overwriting an existing tag.