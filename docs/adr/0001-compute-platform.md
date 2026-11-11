# ADR 0001: Run SwiftKart microservices on Amazon EKS (with managed node groups) in ap-southeast-1

- **Status:** Accepted
- **Date:** 2026-11-10
- **Deciders:** Capstone Group 2 (1 Solutions Architect, 2 DevSecOps, 2 SRE)
- **Author:** Zeyaul Haq (DevSecOps)

## Context

SwiftKart is an e-commerce site that runs **flash sales**. We are building it on the
AWS Containers Retail Store Sample app, which has five microservices
(UI, Catalog, Cart, Orders, Checkout) plus supporting services
(databases, Redis and a message queue for Orders).

These constraints shaped the decision:

- **Team size and skills:** 5 people over a short capstone timeline. All of us have
  hands-on practice with Docker, ECR, ECS and EKS from the course, and use Terraform
  and GitHub Actions.
- **Traffic pattern:** Mostly low, steady traffic, with **sudden large spikes** during
  flash sales. The platform must scale out quickly and scale back in to control cost.
- **Number of services:** 5+ services that call each other, so we need service
  discovery, rolling deployments and per-service scaling.
- **Tooling:** Infrastructure must be written in **Terraform**; build and deploy must
  run through **GitHub Actions**. The sample app already ships **Helm charts** for
  Kubernetes.
- **Compliance:** All data and logs must stay in **ap-southeast-1 (Singapore)**.
  No manual console changes to production — every change must go through Git
  so it is auditable.
- **Cost:** Single AWS account with a limited budget.

## Options considered

### Option 1: Amazon ECS on Fargate

**Pros**
- Simplest to run: no nodes or cluster control plane to manage.
- No control-plane fee; pay only for running tasks.
- Native integration with IAM, ALB, CloudWatch and ECR.
- Smaller learning curve for the team.

**Cons**
- AWS-specific; task definitions and service config do not carry over to other
  platforms.
- We cannot reuse the sample app's Helm charts; we would have to rewrite every
  service as ECS task definitions.
- Fewer ecosystem tools for progressive delivery, policy enforcement and
  autoscaling (for example Argo CD, Kyverno/OPA, Karpenter, KEDA).
- Fargate tasks can be slower to start than pods on already-running nodes during a
  sudden spike.

### Option 2: Amazon EKS with managed node groups (chosen)

**Pros**
- Industry-standard Kubernetes; skills and manifests are portable.
- Reuses the sample app's existing **Helm charts**, saving rewrite effort.
- Strong autoscaling for flash sales: Horizontal Pod Autoscaler for pods, plus
  Cluster Autoscaler or Karpenter for nodes.
- Rich DevSecOps tooling: GitOps (Argo CD), admission policies (Kyverno/OPA),
  network policies, image scanning in the pipeline.
- Clear audit trail: all changes flow through Git -> GitHub Actions -> cluster;
  EKS control-plane logs go to CloudWatch in ap-southeast-1.

**Cons**
- More complex: the team must understand Kubernetes objects, RBAC, IRSA/Pod Identity
  and networking.
- Extra cost: EKS control-plane fee (about USD 0.10/hour) plus EC2 worker nodes.
- We are responsible for node group upgrades and Kubernetes version upgrades.
- Longer to set up and debug than ECS for a small team.

### Option 3 (briefly considered): Containers on plain EC2 with Docker Compose

**Pros**
- Very cheap and easy to understand.

**Cons**
- No real autoscaling or self-healing; would fail under flash-sale spikes.
- Hard to deploy safely and audit; not suitable for production.
- Rejected early.

## Decision

We will run all SwiftKart services on **Amazon EKS with managed node groups** in
**ap-southeast-1**, provisioned with **Terraform** and deployed with **Helm** through
**GitHub Actions**.

**Why:**
1. **Flash-sale scaling:** HPA plus node autoscaling handles sudden spikes and
   scales back down afterwards.
2. **Reuse:** the sample app already has Helm charts, so we spend our time on
   security, observability and reliability instead of rewriting deployment config.
3. **DevSecOps controls:** Kubernetes gives us policy enforcement, network policies
   and GitOps-style deployments, which help meet the "no manual changes, fully
   auditable" requirement.
4. **Learning value:** EKS is a core skill of the course and widely used in industry.

We accept the extra complexity and cost because the team has EKS practice from class
and the scaling and security benefits matter most for this use case.

## Consequences

### What this makes easier
- Scaling individual services (e.g. Checkout and Orders) independently during sales.
- Deploying with existing Helm charts and standard Kubernetes tooling.
- Enforcing security in one place: pod security, network policies, image policies.
- Rolling updates and rollbacks for each service with no downtime.
- Moving to another Kubernetes platform later if needed.

### What this rules out / makes harder
- **Rules out** the "serverless, nothing to manage" model of ECS Fargate; we now own
  node groups and Kubernetes upgrades.
- **Rules out** using ECS task definitions and ECS-specific tooling in our pipeline.
- Higher baseline cost (control plane + always-on nodes), even when traffic is low.
- Steeper learning curve; every team member needs basic `kubectl` and Helm skills.
- More moving parts to secure (cluster RBAC, add-ons, node AMIs).

### Follow-up actions
- Define the EKS cluster, node groups and add-ons in Terraform (infra repo).
- Add a GitHub Actions workflow: build -> scan -> push to ECR -> `helm upgrade`.
- Configure HPA for each service and node autoscaling.
- Send EKS control-plane and application logs to CloudWatch in ap-southeast-1.
