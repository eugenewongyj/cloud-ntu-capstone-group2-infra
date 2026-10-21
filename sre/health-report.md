# 🛒 E-Commerce Application | SRE Health Report

**Project:** Group 2 — E-Commerce Application  
**Environment:** Staging  
**Default AWS Region:** `ap-southeast-1` (Singapore)  
**Report Date:** 21 October 2026  
**Overall Status:** 🚧 Infrastructure Configured — Operational Verification Incomplete

## 👋 About This Report

This report provides a shared view of our e-commerce application's infrastructure, deployment readiness, and operational health.

It helps us answer three questions:

1. **What have we already configured?**
2. **What is still incomplete or unverified?**
3. **What should we check or improve next?**

The report is maintained as part of the SRE workstream and will be updated as our team verifies deployments and introduces monitoring.

> **Important:** A resource defined in Terraform is not necessarily deployed or healthy. Configuration readiness and operational health are tracked separately.

---

## 🏗️ 1. Infrastructure Overview

Our infrastructure is designed to run five e-commerce microservices on Amazon EKS, using AWS networking, container registries, and GitHub Actions deployment workflows.

| Component | Purpose | What's Already Configured | Still Needed |
|---|---|---|---|
| VPC | Provides the application's AWS network | VPC CIDR `10.0.0.0/16` | Verify deployed VPC |
| Public Subnets | Host internet-facing networking resources | Two public subnet definitions | Verify placement and routing |
| Private Subnets | Provide private networking for workloads | Two private subnet definitions | Verify workload connectivity |
| Internet Gateway | Provides internet access through public routes | Gateway and public route defined | Verify connectivity |
| NAT Gateway | Provides outbound internet access for private subnets | One NAT Gateway and Elastic IP defined | Verify outbound connectivity |
| Route Tables | Control network traffic paths | Public/private routes and associations defined | Verify actual routing |
| EKS | Orchestrates application containers | EKS cluster configuration and access outputs | Verify cluster and workloads |
| ECR | Stores application container images | Five repositories with scanning and lifecycle policies | Verify images and image pulls |
| Load Balancer | Routes external traffic to the application | Frontend deployment reported by the team | Verify endpoint and target health |

### 🌐 Network Configuration

| Setting | Configured Value |
|---|---|
| AWS Region | `ap-southeast-1` |
| Project Prefix | `capstone-group2` |
| VPC | `10.0.0.0/16` |
| Public Subnet 1 | `10.0.1.0/24` |
| Public Subnet 2 | `10.0.2.0/24` |
| Private Subnet 1 | `10.0.3.0/24` |
| Private Subnet 2 | `10.0.4.0/24` |
| NAT Gateways | 1 |
| Availability Zones | Dynamically selected from available AZs |

The configuration places public and private subnets across two Availability Zones, subject to the AZs returned for the deployment account.

**Resilience consideration:** Both private subnets use a single NAT Gateway in the first public subnet. This reduces staging costs but creates a shared dependency for outbound connectivity.

### ☸️ EKS Cluster Configuration

The Terraform configuration defines an EKS cluster with:

- Cluster name derived from the project prefix.
- Kubernetes version `1.37`.
- Public and private cluster API endpoint access.
- EKS Auto Mode enabled with `general-purpose` and `system` node pools.
- Private subnet placement.
- Terraform outputs for cluster name, endpoint, certificate authority data, and local `kubectl` configuration.

**Still to verify:**

- [ ] EKS cluster exists in the intended AWS account and region.
- [ ] Cluster is accessible to authorised team members.
- [ ] Compute capacity is available.
- [ ] Application pods are running and ready.
- [ ] Kubernetes Services and ingress/load balancing are functional.

---

## 📦 2. Container Registry — Amazon ECR

Amazon ECR stores the Docker images used to deploy our five application microservices.

| Repository | Application Purpose | Runtime Verification |
|---|---|---|
| `capstone-group2-ui` | Customer-facing storefront | ⏳ Pending |
| `capstone-group2-catalog` | Product catalogue | ⏳ Pending |
| `capstone-group2-carts` | Shopping cart | ⏳ Pending |
| `capstone-group2-orders` | Order management | ⏳ Pending |
| `capstone-group2-checkout` | Checkout operations | ⏳ Pending |

**Already configured:**

- Five ECR repository definitions.
- Mutable image tags.
- Image scanning on push.
- Image lifecycle cleanup policies.
- Terraform output containing repository URLs.

**Still to verify:**

- [ ] All five repositories exist in AWS.
- [ ] Expected container images have been pushed.
- [ ] Image scanning results have been reviewed.
- [ ] EKS can pull the required images.
- [ ] Image retention behaviour is suitable for rollback.

**Configuration review:** The ECR lifecycle policy description says it retains the latest 10 images, but the implemented rule expires images older than 14 days. The team should confirm the intended retention policy.

---

## 🛒 3. Application Health

The application comprises five services that work together to support the customer shopping journey.

| Service | Purpose | Health Check | Status |
|---|---|---|---|
| UI | Displays the online storefront | Frontend responds to HTTP requests | ⏳ Pending |
| Catalog | Provides product information | Product service responds | ⏳ Pending |
| Carts | Manages shopping carts | Cart service responds | ⏳ Pending |
| Orders | Processes customer orders | Order service responds | ⏳ Pending |
| Checkout | Coordinates checkout operations | Checkout service responds | ⏳ Pending |

**Current understanding:** The team previously reported a frontend deployment through an AWS load balancer. Independent HTTP verification and backend service checks have not yet been recorded in this report.

**Still to verify:**

- [ ] Frontend HTTP response and response time.
- [ ] Backend service availability.
- [ ] Product browsing functionality.
- [ ] Cart and checkout functionality.
- [ ] Application errors and latency under load.

---

## 🔐 4. GitHub OIDC & AWS IAM

Our team has configured separate AWS deployment roles for infrastructure and application workflows.

This allows GitHub Actions to request temporary AWS credentials using OIDC, rather than relying on long-lived AWS access keys.

| Component | What's Configured | Still Needed |
|---|---|---|
| GitHub OIDC Provider | Reference to an existing AWS GitHub OIDC provider | Verify provider lookup succeeds |
| Infrastructure IAM Role | `group2-project-infra-deployer-role` | Verify role exists and can be assumed |
| Application IAM Role | `group2-project-app-deployer-role` | Verify role exists and can be assumed |
| Infrastructure IAM Policy | Permissions for EKS, ECR, networking, IAM, logs and supporting resources | Verify required permissions and review scope |
| Application IAM Policy | ECR image-push permissions and EKS cluster-description access | Verify deployment workflow and Kubernetes authorisation |
| OIDC Trust Policies | Repository-based trust conditions | Review wildcard scope and branch/environment restrictions |
| IAM Role Outputs | Separate role ARNs for infrastructure and application pipelines | Verify GitHub repository variables reference the correct roles |

### GitHub Repositories

| Repository | Purpose |
|---|---|
| `eugenewongyj/cloud-ntu-capstone-group2-infra` | Terraform infrastructure and SRE documentation |
| `eugenewongyj/cloud-ntu-capstone-group2-app` | Application source and deployment workflow |

Both repositories are intended to use their corresponding IAM role ARN through the GitHub Actions variable `OIDC_ROLE`.

**Important:** Defining Terraform role outputs does not automatically populate GitHub repository variables or prove that role assumption succeeds.

---

## 🗂️ 5. Terraform State & Dependencies

Our team has configured remote Terraform state in Amazon S3, with separate state files for infrastructure and authentication bootstrap.

| Component | Configuration | Verification Needed |
|---|---|---|
| S3 State Bucket | `sctp-core-tfstate` | Confirm access and protection |
| Infrastructure State | `group2/cloud-ntu-capstone-group2-infra.tfstate` | Verify state is current |
| OIDC Bootstrap State | `group2/group2-github-oidc-bootstrap.tfstate` | Verify authentication resources are tracked |
| Backend Region | `ap-southeast-1` | Confirm backend connectivity |
| Terraform Version | `>= 1.5.0` | Verify pipeline compatibility |
| AWS Provider | `~> 5.0` in root configuration | Review lock-file consistency |
| Supporting Providers | Archive `~> 2.4`, Random `~> 3.5` | Verify provider initialisation |

### Configuration Items Requiring Review

| Item | Observation | Recommended Action |
|---|---|---|
| AWS Provider | Previously shared lock file records `6.69.1`, while root configuration requires `~> 5.0` | Confirm intended provider version and consistent initialisation |
| ECR Lifecycle | Description says 10 images; rule specifies 14 days | Align policy wording and actual behaviour |
| NAT Gateway | Single gateway shared by private subnets | Accept staging trade-off or review resilience needs |
| OIDC Trust | Repository matching uses wildcards | Review least-privilege trust scope |
| Terraform State Protection | Remote S3 backend configured; locking and recovery not confirmed | Verify state access, locking, versioning and recovery |

These are **review items**, not confirmed production incidents.

---

## ⚙️ 6. CI/CD Readiness

| Workflow / Component | What's Present | Status |
|---|---|---|
| Infrastructure Repository | Terraform code and SRE documentation | ✅ Verified |
| Terraform CI | Infrastructure validation workflow configured | ⏳ Latest result pending |
| Terraform CD | Infrastructure deployment workflow configured | ⏳ Latest result pending |
| Terraform Destroy | Infrastructure teardown workflow configured | ⏳ Execution and safeguards unverified |
| GitHub OIDC | Authentication roles and policies defined | ⏳ Runtime verification pending |
| Application Deployment | Application repository and deployment role identified | ⏳ Pipeline verification pending |

A successful deployment workflow does not automatically prove that all application services are healthy. Runtime checks are still required.

---

## 📊 7. SRE Monitoring & Reliability

Our next focus is to move from configuration visibility to measurable application reliability.

| Capability | Why It Matters | Status |
|---|---|---|
| Manual Health Checks | Establish basic service availability | 🚧 In Progress |
| Application Metrics | Measure traffic, errors and latency | 📌 Planned |
| Kubernetes Metrics | Monitor pods, CPU, memory and restarts | 📌 Planned |
| Centralised Logging | Investigate failures across services | ⏳ Not verified |
| Prometheus | Collect and store operational metrics | 📌 Planned |
| Grafana | Visualise service health and trends | 📌 Planned |
| Alertmanager | Route actionable alerts | 📌 Planned |
| SLOs | Define measurable reliability targets | 📌 Planned |
| Incident Response | Guide troubleshooting and recovery | 📌 Planned |

### Initial Reliability Objectives

- Establish availability and latency measurements for the storefront.
- Monitor pod readiness, restarts, CPU and memory usage.
- Track request rates and application errors.
- Define at least two measurable SLOs.
- Configure at least two actionable alerts.
- Verify centralised log collection and retention.
- Prepare a basic incident response procedure.

These are planned objectives, not completed monitoring capabilities.

---

## 🔎 8. Current Findings

### ✅ Confirmed

- Terraform definitions are present for VPC networking, EKS, ECR, and GitHub OIDC/IAM.
- Infrastructure and OIDC bootstrap use separate configured S3 state paths.
- The infrastructure repository is accessible.
- Local AWS CLI authentication succeeded.

### 🚧 Present but Incomplete

- EKS configuration and cluster connection outputs are defined, but cluster health is unverified.
- Five ECR repositories are defined, but image availability and successful pulls are unverified.
- GitHub IAM deployment roles are defined, but role assumption is unverified.
- The frontend deployment was reported by the team, but its live response has not been independently recorded.
- CI/CD workflows are configured, but their latest results have not been recorded.

### ⚠️ Items to Clarify

- The locally authenticated AWS identity returned no EKS clusters in `ap-southeast-1`; confirm the actual deployment account and region.
- Confirm AWS provider version consistency.
- Clarify ECR image retention behaviour.
- Review OIDC trust restrictions and Terraform state protection.

---

## 📋 9. Team's Next Steps

### Priority 1 — Verify What's Running

- [ ] Confirm the actual deployment AWS account, region and EKS cluster.
- [ ] Review the latest infrastructure and application workflow results.
- [ ] Verify frontend HTTP connectivity.
- [ ] Verify EKS pods and backend service connectivity.
- [ ] Verify ECR repositories and container images.

### Priority 2 — Review Configuration

- [ ] Resolve Terraform provider version discrepancy.
- [ ] Clarify ECR lifecycle retention policy.
- [ ] Review OIDC trust policies and deployment access.
- [ ] Verify Terraform state protection.
- [ ] Review single-NAT resilience trade-off.

### Priority 3 — Build Observability

- [ ] Establish baseline application metrics.
- [ ] Verify or introduce centralised logging.
- [ ] Set up Prometheus and Grafana.
- [ ] Define SLOs and alert thresholds.
- [ ] Configure alert routing and incident response documentation.

---

## 🏷️ Status Guide

| Status | Meaning |
|---|---|
| ✅ Verified | Confirmed through a check or direct configuration inspection |
| 🚧 Configured / In Progress | Implementation exists but is incomplete or not fully verified |
| ⏳ Pending | Awaiting verification |
| 📌 Planned | Intended for a later phase |
| ⚠️ Review Needed | A discrepancy or potential risk requires clarification |
| 🔴 Issue | An actual check identified an operational failure |

---

*Maintained by the SRE workstream. This report is intended to make our progress and outstanding work visible to the entire team. We'll update operational statuses as evidence becomes available.*
