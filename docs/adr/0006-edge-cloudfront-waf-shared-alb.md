# ADR 0006: Put CloudFront and AWS WAF in front of the shop, behind one shared Application Load Balancer, in ap-southeast-1

- **Status:** Accepted
- **Date:** 2026-11-28
- **Deciders:** Capstone Group 2 (1 Solutions Architect, 2 DevSecOps, 2 SRE)
- **Author:** [Your name] (Solutions Architect)
- **Related:** ADR 0001 (compute platform), APP-ADR-003 in ADR 0003 (ingress and TLS)

## Context

The **edge** is everything between a shopper's browser and our pods: the web
address, HTTPS, the firewall and the load balancer. It is the first thing a
flash sale hits.

These constraints shaped the decision:

- **Latency (hard constraint):** **p95 ≤ 500 ms on product listing**, including
  during a 10–20× flash-sale spike. Product images, CSS and JavaScript make up much
  of each page, so where they are served from matters.
- **Elasticity (hard constraint):** the edge must absorb the spike without us
  adding or resizing anything by hand.
- **Cost accountability (hard constraint):** fixed monthly charges should be kept
  low, and extra cost should follow real traffic.
- **Security:** the shop is public, so it needs protection from common web attacks
  (for example SQL injection) and from a single client flooding it with requests.
  Attackers must not be able to bypass the firewall by going straight to the
  load balancer.
- **Several public sites:** besides the shop, the team exposes the staging shop,
  Argo CD and Grafana. Each needs HTTPS.
- **Tooling:** the load balancer is created by EKS Auto Mode from Kubernetes
  Ingress objects; everything else is written in **Terraform**.

## Options considered

### Option 1: One ALB per site, no CDN

**Pros**
- Simplest to understand: each site has its own load balancer.
- A problem with one site's load balancer cannot affect the others.

**Cons**
- **4 ALBs instead of 1.** Each ALB has a fixed hourly charge plus public IP
  charges, about **$25 a month each**, so 3 extra ALBs add about **$75 a month**
  with no benefit to shoppers.
- Every request, including every image, travels to Singapore and through our pods.
  During a sale the pods spend capacity serving files that never change.
- No firewall in front of the shop unless one is added to each ALB separately.

### Option 2: CloudFront + AWS WAF in front of one shared ALB (chosen)

**Pros**
- **Faster pages:** CloudFront keeps copies of `/assets/*` (product images, CSS,
  JavaScript) at edge locations close to shoppers, so those files load without
  reaching our cluster. This helps the p95 target.
- **Less load during a sale:** cached files are served by CloudFront, so pods and
  nodes only handle the dynamic pages (catalog, cart, checkout, orders).
- **Scales automatically:** CloudFront and the ALB grow with traffic on their own;
  there is nothing to size for a 20× spike.
- **Pay for use:** CloudFront and WAF are charged mainly per request, so most of
  their cost follows traffic.
- **Protection at the edge:** WAF blocks common attacks and rate-limits any single
  IP before the request reaches Singapore.
- **One ALB for all sites:** the shop, staging shop, Argo CD and Grafana share one
  ALB (Ingress group `group2-shared`), saving about **$75 a month**.

**Cons**
- More moving parts: a CloudFront distribution, two WAFs and two certificates
  (one in us-east-1, as CloudFront requires).
- Changes to CloudFront take several minutes to roll out worldwide.
- CloudFront is the largest single line in our traffic cost: about **$6.57** of the
  **$10** a 2-hour sale adds, and about **$124 a month** at baseline in our model.
- One shared ALB means a misconfigured Ingress could affect every site on it.

### Option 3: ALB + WAF only, no CDN

**Pros**
- Cheaper than Option 2 on a quiet day (no CloudFront charges).
- One less service to configure.

**Cons**
- Every image and script still travels to Singapore and through our pods,
  which costs latency and pod capacity during a sale.
- The firewall only acts once traffic has reached our region.

## Decision

We will serve the shop through **Amazon CloudFront** with **AWS WAF**, in front of
**one shared Application Load Balancer** in **ap-southeast-1**, provisioned with
**Terraform** (`cloudfront.tf`, `waf.tf`, `acm.tf`) and Kubernetes Ingress
(`group2-shared`).

How a shopper's request flows:

```
Shopper → https://group2-shop.sctp-sandbox.com
        → CloudFront + edge WAF (cache /assets/*, block attacks, rate limit)
        → https://group2-retail.sctp-sandbox.com (shared ALB + regional WAF)
        → ui pods in EKS
```

As deployed:

| Part | Setting | Why |
| --- | --- | --- |
| CloudFront caching | Only `/assets/*` is cached; all other pages are not cached | Static files are safe to cache; prices, stock, carts and orders must always be live |
| CloudFront locations | `PriceClass_200` | Includes Asian edge locations near Singapore shoppers, without paying for every location worldwide |
| HTTPS | Both legs (shopper → CloudFront, CloudFront → ALB); TLS 1.2 minimum; HTTP redirected to HTTPS | Encryption in transit |
| Edge WAF (on CloudFront) | AWS Common Rule Set, AWS Known Bad Inputs, **RateLimitPerIP 2,000 requests per 5 minutes** (block) | Stop attacks and floods before they reach our region; the rate limit sees real shopper IPs here |
| Regional WAF (on the ALB) | Rule `ShopOnlyViaCloudFront`, plus the two AWS rule sets | Blocks shop requests that do not carry CloudFront's secret `X-Origin-Verify` header, so nobody can bypass the edge WAF |
| Shared ALB | One ALB for the shop, staging shop, Argo CD and Grafana | Saves about $75 a month |
| Logs | CloudFront access logs to an S3 bucket in Singapore | Audit trail; data stays in ap-southeast-1 |

The secret header value is generated by Terraform and kept only in Terraform state,
never in the public repo.

**Why:**
1. **Latency:** cached assets load from an edge location near the shopper, so the
   pods only build the product list itself. This supports p95 ≤ 500 ms.
2. **Elasticity:** CloudFront and the ALB scale on their own, and caching reduces
   how much the cluster has to scale.
3. **Cost accountability:** one ALB instead of four saves about $75 a month, and
   CloudFront and WAF charges mostly follow traffic.
4. **Security:** two layers of WAF, with the ALB locked so that shop traffic must
   come through CloudFront.

We accept the extra moving parts and CloudFront's per-request cost because faster
pages and protection at the edge matter most during a flash sale.

## Consequences

### What this makes easier
- Keeping product pages fast during a sale, because images and scripts are served
  from the edge.
- Absorbing traffic spikes with no manual action at the edge.
- Blocking common attacks and single-IP floods before they reach Singapore.
- Adding another internal site: it joins the same ALB with a new Ingress host rule,
  at no extra fixed cost.
- Showing the cost of a sale: most edge cost is per request, so it maps directly
  to traffic.

### What this rules out / makes harder
- **Dynamic pages are not cached.** The product list itself is still built by the
  catalog service and Aurora on every request, so the cluster must still scale for
  the sale.
- **The rate limit can block legitimate load.** 2,000 requests per 5 minutes per IP
  fits a normal shopper, but our in-cluster k6 load test leaves through one NAT IP
  and can exceed it at 20×. The test traffic would then be blocked at CloudFront
  instead of reaching the pods. Shoppers behind one shared office or mobile-carrier
  IP could also be affected.
- **One shared ALB is a shared point of failure:** a broken Ingress rule or an ALB
  problem affects the shop, staging, Argo CD and Grafana together.
- **The ALB-level rule protects the shop only.** Argo CD, Grafana and the staging
  shop are reached directly on the ALB, protected by the regional WAF rules and
  their own logins, but not by CloudFront.
- **CloudFront changes are slow to roll out** (several minutes), so emergency edge
  fixes are not instant.

### Follow-up actions
- Before a load test, check the `cdn-rate-limit` WAF metric. Raise
  `waf_rate_limit_per_ip` or exempt the NAT gateway IPs for the test, so the load
  reaches the pods.
- Review the rate limit against real shopper traffic after the first sale.
- Consider restricting Argo CD and Grafana by IP address, or moving them to a
  separate internal ALB.
- Consider caching the product list for a few seconds at the edge if p95 nears
  500 ms at higher multipliers.
