# DevOps Assignment 

End-to-end infrastructure, deployment automation, and monitoring stack on AWS, built with Terraform, EKS, and GitHub Actions.

## Architecture Overview

```
                                   Internet
                                       │
                         ┌─────────────┴─────────────┐
                         │      Public Subnets        │
                         │   (2 AZs, IGW attached)    │
                         │                             │
                         │   ┌─────────┐   ┌────────┐ │
                         │   │ Bastion │   │  NAT   │ │
                         │   │  (SSM+  │   │Gateway │ │
                         │   │  SSH)   │   └────────┘ │
                         │   └────┬────┘              │
                         └────────┼───────────────────┘
                                  │
                         ┌────────┼───────────────────┐
                         │     Private Subnets         │
                         │                              │
                         │   ┌──────────────────┐      │
                         │   │   EKS Cluster     │      │
                         │   │  (managed node    │      │
                         │   │   group, t3.small)│      │
                         │   │                    │      │
                         │   │  ┌──────────────┐  │      │
                         │   │  │ Sample App   │  │      │
                         │   │  │ (2 replicas) │  │      │
                         │   │  └──────┬───────┘  │      │
                         │   │  ┌──────┴───────┐  │      │
                         │   │  │ Prometheus + │  │      │
                         │   │  │ Grafana      │  │      │
                         │   │  └──────────────┘  │      │
                         │   └──────────┬─────────┘      │
                         │              │                 │
                         │   ┌──────────┴─────────┐      │
                         │   │   RDS PostgreSQL     │      │
                         │   │   (Multi-AZ: off,    │      │
                         │   │    encrypted, 7d      │      │
                         │   │    backups)           │      │
                         │   └──────────────────────┘      │
                         └──────────────────────────────────┘

  ECR (container images) ←── GitHub Actions CI/CD ──→ Secrets Manager (DB creds)
```

## Tech Stack

| Layer | Technology |
|---|---|
| IaC | Terraform (modular: vpc, security_groups, eks, rds, ecr, bastion) |
| Compute | Amazon EKS (managed node group) |
| Database | RDS PostgreSQL 16.3 |
| Container Registry | Amazon ECR |
| CI/CD | GitHub Actions |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack via Helm) |
| Logging | Loki + Promtail |
| Secrets | AWS Secrets Manager |
| Access | Bastion host (SSM Session Manager + SSH) |

## Prerequisites

- AWS account with programmatic access (IAM user with sufficient permissions)
- Terraform >= 1.5.0
- AWS CLI v2, configured (`aws configure`)
- kubectl, Helm 3, Docker
- An existing EC2 key pair for bastion SSH access

## Setup Instructions

### 1. Bootstrap remote state (one-time, manual)

```bash
aws s3api create-bucket --bucket <your-unique-bucket-name> --region us-east-1
aws s3api put-bucket-versioning --bucket <your-unique-bucket-name> --versioning-configuration Status=Enabled
```

Update `terraform/backend.tf` with your bucket name.

### 2. Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — set at minimum:
```hcl
bastion_key_pair_name    = "your-key-pair-name"
bastion_allowed_ssh_cidr = "your-ip/32"   # or 0.0.0.0/0 for demo convenience
```

### 3. Provision infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Takes ~15-20 minutes (EKS control plane provisioning is the majority of this).

### 4. Build and push the application image

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

cd app
docker build -t sample-app .
docker tag sample-app:latest <ecr_repository_url>:v1
docker push <ecr_repository_url>:v1
```

### 5. Connect to the cluster (via bastion)

```bash
ssh -i jumphost.pem ec2-user@<bastion_public_ip>
aws eks update-kubeconfig --name devops-assignment-eks --region us-east-1
kubectl get nodes
```

### 6. Deploy the application

```bash
kubectl apply -f manifests/00-namespace.yaml

# Pull DB credentials from Secrets Manager into a K8s secret
secret=$(aws secretsmanager get-secret-value --secret-id devops-assignment/rds/credentials --region us-east-1 --query SecretString --output text)
kubectl create secret generic rds-credentials \
  --namespace devops-assignment \
  --from-literal=host=$(echo $secret | jq -r .host) \
  --from-literal=dbname=$(echo $secret | jq -r .dbname) \
  --from-literal=username=$(echo $secret | jq -r .username) \
  --from-literal=password=$(echo $secret | jq -r .password)

kubectl apply -f manifests/01-deployment.yaml
kubectl apply -f manifests/02-service.yaml
kubectl apply -f manifests/03-hpa.yaml
```

### 7. Install monitoring stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f monitoring/prometheus-values.yaml \
  --set grafana.adminPassword='<choose-a-password>' \
  --wait --timeout 15m
```

### 8. Access services (demo/dev — see Known Limitations)

```bash
# From local machine, tunnel through the bastion:
ssh -i jumphost.pem -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 ec2-user@<bastion-ip>

# On the bastion, in the same session:
kubectl port-forward svc/sample-app-svc -n devops-assignment 8080:80 &
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
```

Then open `http://localhost:8080` (app), `http://localhost:3000` (Grafana), `http://localhost:9090` (Prometheus) locally.

## Architecture Decisions

- **EKS over ECS/EC2**: chosen to demonstrate Kubernetes orchestration depth (managed node groups, IRSA, CSI drivers, HPA) — a heavier but more broadly applicable skill set than ECS or static EC2/ASG.
- **Bastion host with dual access (SSM + SSH)**: SSM Session Manager is the preferred path (no open inbound port, all access logged via CloudTrail); SSH is retained for convenience during development. In production, SSH would be removed in favor of SSM-only.
- **Secrets Manager over hardcoded credentials**: RDS master password is auto-generated by Terraform (`random_password`) and never appears in code, state diffs, or `.tfvars`. Application pods read credentials via a Kubernetes Secret populated from Secrets Manager at deploy time.
- **Modular Terraform**: each concern (vpc, security_groups, eks, rds, ecr, bastion) is an isolated module with explicit inputs/outputs — improves readability and reuse over a single monolithic `main.tf`.
- **t3.small node instances**: the AWS account in use enforces Free Tier instance-type restrictions; `t3.medium` and larger were rejected at the API level. `t3.small` was the largest permitted type, which is undersized for a full EKS + monitoring stack workload — documented as a test-environment constraint, not a production recommendation.

## Security Considerations

- All application-tier resources (EKS nodes, RDS) sit in **private subnets** with no direct internet exposure.
- Security groups follow least privilege: internet → ALB/bastion only → EKS nodes (via EKS's own cluster SG) → RDS. No security group allows `0.0.0.0/0` except the bastion's SSH rule (see Known Limitations) and the (removed) internet-facing load balancer's HTTP/HTTPS.
- RDS storage is encrypted at rest (`storage_encrypted = true`); `publicly_accessible = false`.
- Database credentials are never stored in source control; generated randomly by Terraform and stored in Secrets Manager, injected into pods via Kubernetes Secrets at deploy time.
- EKS cluster uses IAM Roles for Service Accounts (IRSA) via an OIDC provider for the EBS CSI driver, rather than broad node-level IAM permissions — least-privilege access scoped to the specific service account.
- Bastion SSH is currently open to `0.0.0.0/0` for assignment/demo convenience — **documented as a known simplification**; production would restrict to a specific CIDR or rely exclusively on SSM.

## Cost Optimization

- NAT Gateway is toggleable via `enable_nat_gateway` variable — can be disabled to eliminate hourly NAT charges when private-subnet outbound internet isn't required.
- RDS `db.t3.micro`, single-AZ, `backup_retention_period` tuned to the account's Free Tier maximum.
- EKS node group sized to Free Tier-permitted instance types only.
- ECR lifecycle policy retains only the last 10 images, bounding storage cost.
- All resources are destroyable via `terraform destroy` — recommended immediately after grading/demo to stop billing.

## Known Limitations

- **No internet-facing load balancer**: the AWS account in use has ELB/ALB/NLB creation disabled at the account level (`OperationNotPermitted` — confirmed via AWS Load Balancer Controller logs, not a configuration issue). Services are accessed via `kubectl port-forward` through the bastion for demo purposes. Lifting this requires an AWS Support request; the Terraform and Kubernetes configuration is otherwise ready to provision a real NLB the moment the restriction is lifted (see `docs/CHALLENGES.md`).
- **EKS control plane API is publicly accessible** (`endpoint_public_access = true`) for operational simplicity within the assignment timeline; production would restrict `public_access_cidrs` or go fully private behind the bastion/VPN.
- **t3.small nodes**: undersized for a production EKS + full monitoring stack workload; sufficient for this demo given account restrictions.

## Repository Structure

```
.
├── terraform/          # Infrastructure as Code (modular)
├── app/                 # Sample Node.js/Express app (RDS-connected)
├── manifests/           # Kubernetes manifests (namespace, deployment, service, HPA)
├── monitoring/           # Prometheus/Grafana/Loki Helm values
├── .github/workflows/    # CI/CD pipeline
└── docs/
    ├── APPROACH.md
    └── CHALLENGES.md
```