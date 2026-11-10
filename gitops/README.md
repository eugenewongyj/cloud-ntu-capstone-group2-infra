This repository contains the complete **GitOps Infrastructure-as-Code (IaC)** for provisioning and managing the eks cluster on AWS EKS. It leverages **Argo CD** and the **App of Apps** pattern to fully automate the deployment of core infrastructure, observability (SRE) tooling, and business applications.

## 📂 Repository Architecture

The deployment is strictly ordered using Argo CD `sync-wave` annotations to prevent race conditions (e.g., ensuring CRDs and Ingress controllers exist before deploying applications that depend on them).

*   **`bootstrap/`**: Contains `init.sh` (bootstrap script), `root.yaml` (the App of Apps entry point), and Argo CD Helm values.
*   **`infra/`**: Core cluster infrastructure (Ingress NGINX, Cert-Manager, External-DNS, StorageClass).
*   **`sre/`**: Observability stack (kube-prometheus-stack, Grafana Alloy, Prometheus CRDs).
*   **`app/`**: Workload microservices (Sample).
*   **`destroy.sh`**: A robust teardown script that safely strips finalizers, cleans up AWS resources (NLBs), and purges namespaces.

### Deployment Sequence (Sync Waves)
1.  **Wave -5**: Prometheus CRDs (`prometheus-operator-crds`)
2.  **Wave -2**: Root Infra App (triggers Ingress, Cert-Manager, External-DNS)
3.  **Wave -1**: Root SRE App (triggers Monitoring stack)
4.  **Wave 0**: Root App (triggers Business Workloads)
5.  **Internal Waves**: Ingress (`-1`) -> Cert-Manager (`0`) -> ClusterIssuer (`1`) -> SRE (`3`) -> Workload microservices (`4`)

---

## 🛠️ Bootstrap the Cluster

To bootstrap the entire cluster from scratch, run the initialization script:

```bash
chmod +x init.sh
./init.sh
```
## Accessing Platform Dashboards

After successfully running `./init.sh`, the core platform UI dashboards will be provisioned. Use the commands below to retrieve your initial admin passwords.

### 1. Argo CD
Argo CD orchestrates our GitOps deployments and provides a UI to monitor application health and sync status.

* **URL:** [https://group2-capstone-argocd.sctp-sandbox.com](https://group2-capstone-argocd.sctp-sandbox.com)
* **Username:** `admin`
* **Retrieve Password:**
  Run the following command to decode the initial admin password from the Kubernetes secret:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo


### 2. Grafana (Prometheus Monitoring Stack)
Grafana provides cluster observability, metrics, and alerting dashboards, deployed via the kube-prometheus-stack.

* **URL:** [https://group2-capstone-grafana.sctp-sandbox.com](https://group2-capstone-grafana.sctp-sandbox.com)
* **Username:** `admin`
* **Retrieve Password:**
  Run the following command to decode the initial admin password from the Kubernetes secret:
  ```bash
  kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d && echo


### The Core Philosophy: GitOps
**Git is the single source of truth** for your cluster's desired state. You do not run `kubectl apply` or `helm install` manually to deploy applications. Instead, you update files in this Git repository, and Argo CD ensures the Kubernetes cluster exactly matches what is in Git.

### The Reconciliation Loop
Argo CD operates on a continuous **Reconciliation Loop**. It constantly asks three questions:
1. **What is the Desired State?** (What does the YAML/Helm chart in this Git repo say?)
2. **What is the Live State?** (What is currently actually running in the Kubernetes cluster?)
3. **Do they match?**
   * If **Yes**: The Application status is marked as **`Synced`** and **`Healthy`**.
   * If **No**: The Application status is marked as **`OutOfSync`**. Depending on the `syncPolicy`, Argo CD will either wait for a manual approval or automatically apply the changes.

### Key Concepts Used in This Repository

#### 1. Applications & AppProjects
*   **Application**: A Kubernetes Custom Resource (CRD) that links a Git repository to a target Kubernetes cluster/namespace.
*   **AppProject**: A logical grouping that acts as a security boundary. You have `infra-project`, `sre-project`, and `app-project`. These restrict where applications can deploy (e.g., an app in `app-project` cannot accidentally deploy into the `kube-system` namespace).

#### 2. The "App of Apps" Pattern
Instead of manually creating hundreds of Applications, you create one "Root" Application (`root.yaml`) that points to a directory in Git containing *other* Application YAML files.
*   `root.yaml` deploys `root-infra.yaml`, `root-sre.yaml`, and `root-app.yaml`.
*   Argo CD sees those new applications and deploys them, creating a cascading tree of deployments.

#### 3. Sync Waves (Dependency Management)
Applying files out of order causes errors (e.g., trying to create an Ingress before the Ingress Controller exists). Argo CD solves this using the **`argocd.argoproj.io/sync-wave`** annotation. 
*   Argo CD sorts all resources by their wave number (lowest to highest) and waits for each wave to become "Healthy" before moving to the next. 
*   **Example:** The Ingress NGINX is at `Wave -1`, so it is fully provisioned and AWS assigns an NLB *before* Cert-Manager (`Wave 0`) tries to provision SSL certificates through it.

#### 4. Automated Sync Policy (Prune & Self-Heal)
In the Application manifests, you will see:
```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
