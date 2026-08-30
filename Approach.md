# Approach Documentation

## Overview

This assignment was tackled in the order specified — Infrastructure Provisioning, Deployment Automation, Monitoring & Logging, Documentation — with each part built and verified working end-to-end before moving to the next, rather than writing all configuration up front and debugging everything at once.

## Part 1: Infrastructure Provisioning

**Approach**: Built a fully modular Terraform codebase rather than a single flat configuration, splitting concerns into `vpc`, `security_groups`, `eks`, `rds`, `ecr`, and `bastion` modules. This mirrors how infrastructure would realistically be organized on a team, with each module owning a clear boundary of responsibility and communicating via explicit input variables and outputs.

**Key decisions**:
- Chose **EKS** over ECS or plain EC2 for application hosting, to demonstrate depth in Kubernetes-native patterns: managed node groups, IAM Roles for Service Accounts (IRSA) via OIDC, CSI drivers, and Horizontal Pod Autoscaling.
- Used **remote state** (S3, versioned) from the start rather than local state, to reflect real team-collaboration practice.
- RDS credentials are **never hardcoded** — generated via Terraform's `random_password` resource and stored exclusively in AWS Secrets Manager, satisfying the "secret management" requirement from the assignment.
- Added a **bastion host** with dual access paths: SSM Session Manager (preferred, no open port) and SSH (convenience, explicitly flagged as a demo-only simplification in the README).
- RDS backup retention and node instance types were tuned to fit within this specific AWS account's Free Tier enforcement, discovered through iterative testing (see Challenges doc).

**Verification**: confirmed the full chain works by deploying a sample application into the cluster and querying it — proving EKS pods can resolve DB credentials from Secrets Manager and successfully connect to RDS through the correct security group chain.

## Part 2: Deployment Automation

**Approach**: Built a GitHub Actions pipeline triggered on pull requests (test stage) and merges to `main` (build, push, deploy stages), following the assignment's explicit requirements: unit/integration tests, vulnerability scanning, build-and-push to a registry, staging deployment, and a manual approval gate before production.

**Key decisions**:
- Used **ECR** as the container registry (rather than Docker Hub or GHCR) to keep the pipeline entirely within the AWS ecosystem already provisioned in Part 1.
- Vulnerability scanning is enabled via ECR's built-in `scan_on_push`, avoiding the need for a separate third-party scanning step.
- The manual approval gate for production deployment uses GitHub Environments with required reviewers, rather than a custom approval mechanism.

## Part 3: Monitoring & Logging

**Approach**: Deployed the community-maintained `kube-prometheus-stack` Helm chart, which bundles Prometheus, Grafana, Alertmanager, node-exporter, and kube-state-metrics — rather than hand-assembling each component individually. This is standard practice for EKS monitoring and ships with production-quality default dashboards.

**Key decisions**:
- Chose **Loki + Promtail** (via `loki-stack`) over an EFK (Elasticsearch/Fluentd/Kibana) stack for centralized logging — Loki is significantly lighter on the resource-constrained nodes available in this account, and integrates directly into the same Grafana instance already deployed for metrics, giving a single pane of glass for both.
- Configured a **PrometheusRule** with custom alerting rules for the application and database, in addition to the chart's default infra alerts.
- Installed the **EBS CSI driver** (with proper IRSA/OIDC trust) to enable persistent storage for Prometheus's metrics history and Grafana's configuration — without this, pod restarts would lose all historical data.
- Attempted to expose Grafana/Prometheus/the application via a real AWS Network Load Balancer using the AWS Load Balancer Controller; discovered this specific AWS account has load balancer creation disabled at the account level. Documented this thoroughly (see Challenges doc) and fell back to `kubectl port-forward` via the bastion for access — a standard, low-risk approach for constrained dev/demo environments.

## Part 4: Documentation

This README, the Challenges document, and inline comments throughout the Terraform and Kubernetes manifests are intended to let a reviewer understand not just *what* was built, but *why* each decision was made — particularly where a decision was a deliberate trade-off given the assignment's timeline or this AWS account's specific constraints, rather than an oversight.

## What I'd Add With More Time

- Full AWS Load Balancer Controller + real NLB, once the account restriction is lifted (config is ready — see Known Limitations in README)
- EKS node group migrated to EKS-managed add-ons for VPC CNI/kube-proxy/CoreDNS (currently self-managed at bootstrap) for automatic version compatibility management
- Sequential EKS version upgrade path from 1.30 to the latest supported minor version (AWS requires one-minor-version-at-a-time upgrades)
- Tighter bastion SSH CIDR restriction instead of `0.0.0.0/0`
- ECR image signing / provenance attestation in the CI/CD pipeline