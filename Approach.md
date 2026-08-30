# Approach Documentation

## Overview

This assignment was tackled in the order specified — Infrastructure
Provisioning, Deployment Automation, Monitoring & Logging, Documentation —
with each part built and verified working end-to-end before moving to the
next, rather than writing all configuration up front and debugging
everything at once.

## Part 1: Infrastructure Provisioning

**Approach**: Built a fully modular Terraform codebase rather than a single
flat configuration, splitting concerns into `vpc`, `security_groups`, `eks`,
`rds`, `ecr`, and `bastion` modules. This mirrors how infrastructure would
realistically be organized on a team, with each module owning a clear
boundary of responsibility and communicating via explicit input variables
and outputs.

**Key decisions**:
- Chose **EKS** over ECS or plain EC2 for application hosting, to
  demonstrate depth in Kubernetes-native patterns: managed node groups, IAM
  Roles for Service Accounts (IRSA) via OIDC, CSI drivers, and Horizontal
  Pod Autoscaling.
- Used **remote state** (S3 bucket `devops-assignment-terraform-state-jksdfa`,
  versioned) from the start rather than local state, to reflect real
  team-collaboration practice.
- RDS credentials are **never hardcoded** — generated via Terraform's
  `random_password` resource and injected into the application via a
  Kubernetes Secret, satisfying the "secret management" requirement from
  the assignment.
- Added a **bastion host** for SSH access to the private-subnet EKS
  control-plane API and for running `kubectl`/`helm` against the cluster.
- RDS backup retention and node instance types were tuned to fit within
  this specific AWS account's Free Tier enforcement, discovered through
  iterative testing — see `CHALLENGES.pdf`, item 1.

**Verification**: confirmed the full chain works by deploying the sample
application into the cluster and querying it — proving EKS pods can
resolve DB credentials and successfully connect to RDS through the correct
security group chain (the correct chain being EKS's auto-created cluster
security group, not a manually-created one — see `CHALLENGES.pdf`, item 4).

## Part 2: Deployment Automation

**Approach**: Built a GitHub Actions pipeline (`.github/workflows/ci-cd.yml`)
triggered on pull requests (test stage) and pushes to `dev`/`main` (build,
push, staging deploy), following the assignment's explicit requirements:
unit/integration tests, vulnerability scanning, build-and-push to a
registry, staging deployment, and a manual approval gate before production.

**Key decisions**:
- Used **ECR** as the container registry (rather than Docker Hub or GHCR)
  to keep the pipeline entirely within the AWS ecosystem already
  provisioned in Part 1. ECR's tag immutability is enabled, so every image
  is tagged with the Git commit SHA rather than a mutable `:latest` — this
  also makes every deployed image traceable to an exact commit.
- Vulnerability scanning is done with **Trivy**, run twice: once as a
  filesystem scan against `app/` dependencies before the image is even
  built, and once against the built image itself, so a vulnerable
  dependency is caught before wasting a build.
- Unit/integration tests use **Jest + Supertest** against the Express app,
  with `pg` mocked so tests run without a real database connection —
  needed since GitHub-hosted runners can't reach the private-subnet RDS
  instance directly.
- The manual approval gate for production deployment uses **GitHub
  Environments** with a required reviewer on the `production` environment,
  rather than a custom approval mechanism — the job simply pauses until
  approved in the Actions UI.
- CI/CD authenticates to AWS as a **dedicated, least-privilege IAM user**
  (ECR push/pull on the one repository, plus `eks:DescribeCluster`), with a
  separate namespace-scoped EKS access entry for actual `kubectl` access —
  not the account's admin credentials or the bastion's role.
- Failures at any pipeline stage post to **Slack** via an incoming webhook.

## Part 3: Monitoring & Logging

**Approach**: Deployed the community-maintained `kube-prometheus-stack`
Helm chart, which bundles Prometheus, Grafana, Alertmanager, node-exporter,
and kube-state-metrics — rather than hand-assembling each component
individually.

**Key decisions**:
- Chose **Loki + Promtail** (via `loki-stack`) over an EFK
  (Elasticsearch/Fluentd/Kibana) stack for centralized logging — Loki is
  significantly lighter on the resource-constrained nodes available in this
  account, and integrates directly into the same Grafana instance already
  deployed for metrics, giving a single pane of glass for both.
- RDS is external to the cluster, so its metrics are collected via a
  standalone `prometheus-postgres-exporter` release connecting outward to
  RDS, rather than a sidecar (not possible against a managed database).
- Configured a **PrometheusRule** with custom alerting rules for the
  application (error rate, latency) and database (connection pool
  pressure, availability), in addition to the chart's default infra alerts.
- Installed the **EBS CSI driver** (with a correctly-scoped IRSA/OIDC trust
  policy — see `CHALLENGES.pdf`, item 5) to enable persistent storage for
  Prometheus's metrics history and Grafana's configuration, so pod restarts
  don't lose historical data.
- Attempted to expose Grafana/Prometheus/the application via a real AWS
  Network Load Balancer using the AWS Load Balancer Controller; discovered
  this specific AWS account has load balancer creation disabled at the
  account level (`OperationNotPermitted`, confirmed via the controller's
  own logs — not a Kubernetes or Terraform misconfiguration). Documented
  this in full in `CHALLENGES.pdf`, item 7, and fell back to
  `kubectl port-forward` via the bastion for access — a standard, low-risk
  approach for constrained dev/demo environments, and the reason the
  README's access instructions use port-forwarding rather than a public URL.

Full setup detail: [`monitoring/README.md`](monitoring/README.md).

## Part 4: Documentation

`README.md`, this document, `CHALLENGES.pdf`, and inline comments
throughout the Terraform and Kubernetes manifests are intended to let a
reviewer understand not just *what* was built, but *why* each decision was
made — particularly where a decision was a deliberate trade-off given the
assignment's timeline or this AWS account's specific constraints, rather
than an oversight.

## What I'd Add With More Time

- Full AWS Load Balancer Controller + real NLB, once the account
  restriction is lifted (configuration is already in place — see
  `CHALLENGES.pdf`, item 7)
- EKS-managed add-ons for VPC CNI/kube-proxy/CoreDNS for automatic version
  compatibility management
- Sequential EKS version upgrade path from 1.30 to the latest supported
  minor version (AWS requires one-minor-version-at-a-time upgrades)
- Tighter bastion SSH CIDR restriction instead of a broad allow-list
- ECR image signing / provenance attestation in the CI/CD pipeline
- A generated, committed `package-lock.json` produced by CI itself (the
  local dev machine initially lacked Node/npm — see `CHALLENGES.pdf` for
  how this and related local-tooling gaps were worked around)