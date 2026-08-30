# DevOps Assignment

End-to-end infrastructure, deployment automation, and monitoring stack on AWS,
built with Terraform, EKS, and GitHub Actions.

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
                         │   │  (SSH)  │   │Gateway │ │
                         │   └────┬────┘   └────────┘ │
                         └────────┼───────────────────┘
                                  │
                         ┌────────┼───────────────────┐
                         │     Private Subnets         │
                         │                              │
                         │   ┌──────────────────┐      │
                         │   │   EKS Cluster     │      │
                         │   │  (managed node    │      │
                         │   │   group)          │      │
                         │   │                    │      │
                         │   │  ┌──────────────┐  │      │
                         │   │  │ sample-app   │  │      │
                         │   │  │ (2 replicas) │  │      │
                         │   │  └──────┬───────┘  │      │
                         │   │  ┌──────┴───────┐  │      │
                         │   │  │ Prometheus + │  │      │
                         │   │  │ Grafana +    │  │      │
                         │   │  │ Loki         │  │      │
                         │   │  └──────────────┘  │      │
                         │   └──────────┬─────────┘      │
                         │              │                 │
                         │   ┌──────────┴─────────┐      │
                         │   │   RDS PostgreSQL     │      │
                         │   │   (encrypted at rest) │      │
                         │   └──────────────────────┘      │
                         └──────────────────────────────────┘

  ECR (container images) ←── GitHub Actions CI/CD ──→ Kubernetes Secrets (DB creds)
```

## Tech Stack

| Layer | Technology |
|---|---|
| IaC | Terraform (modular: vpc, security_groups, eks, rds, ecr, bastion) |
| Compute | Amazon EKS (managed node group) |
| Database | RDS PostgreSQL |
| Container Registry | Amazon ECR |
| CI/CD | GitHub Actions |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack via Helm) |
| DB metrics | prometheus-postgres-exporter |
| Logging | Loki + Promtail |
| Access | Bastion host (SSH) |

## Prerequisites

- AWS account with programmatic access (IAM user with sufficient permissions)
- Terraform >= 1.5.0
- AWS CLI v2, configured (`aws configure`)
- kubectl, Helm 3, Docker, Node.js 20+ (for local app testing)
- An existing EC2 key pair for bastion SSH access

## Setup Instructions

### 1. Bootstrap remote state (one-time, manual)

```bash
aws s3api create-bucket --bucket devops-assignment-terraform-state-jksdfa --region us-east-1
aws s3api put-bucket-versioning --bucket devops-assignment-terraform-state-jksdfa --versioning-configuration Status=Enabled
```

`terraform/backend.tf` is already configured to use this bucket.

### 2. Configure variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — set at minimum your bastion key pair name and the
CIDR block allowed to SSH into the bastion. Do not commit this file
(`.gitignore` already excludes it).

### 3. Provision infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Takes roughly 15-20 minutes — EKS control plane provisioning is the majority
of this.

### 4. Build and push the application image

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 691831300312.dkr.ecr.us-east-1.amazonaws.com

cd app
docker build -t sample-app .
docker tag sample-app:latest 691831300312.dkr.ecr.us-east-1.amazonaws.com/devops-assignment/digital-app:v1
docker push 691831300312.dkr.ecr.us-east-1.amazonaws.com/devops-assignment/digital-app:v1
```

In practice, the GitHub Actions pipeline (`.github/workflows/ci-cd.yml`)
handles this automatically on every merge to `dev`/`main` — see Part 2 below.

### 5. Connect to the cluster (via bastion)

```bash
ssh -i jumphost.pem ec2-user@<bastion_public_ip>
aws eks update-kubeconfig --name devops-assignment-eks --region us-east-1
kubectl get nodes
```

### 6. Deploy the application

```bash
kubectl apply -f manifests/namespace.yaml

# Create the DB credentials secret (pull real values from your RDS instance/Terraform outputs)
kubectl create secret generic rds-credentials \
  --namespace devops-assignment \
  --from-literal=host=<rds-endpoint> \
  --from-literal=dbname=<db-name> \
  --from-literal=username=<db-username> \
  --from-literal=password=<db-password>

kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
kubectl apply -f manifests/hpa.yaml
```

### 7. Install the monitoring and logging stack

```bash
kubectl create namespace monitoring

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Grafana admin credentials, created as a Secret rather than typed into values.yaml
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -base64 18)"

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f monitoring/prometheus-values.yaml \
  --set grafana.admin.existingSecret=grafana-admin-credentials \
  --set grafana.admin.userKey=admin-user \
  --set grafana.admin.passwordKey=admin-password

kubectl apply -f monitoring/prometheus-rules.yaml

# DB metrics: RDS is external to the cluster, so this runs as its own release
kubectl create secret generic rds-postgres-exporter-secret \
  --namespace monitoring \
  --from-literal=data-source-name="postgresql://<user>:<password>@<rds-endpoint>:5432/<db>?sslmode=require"

helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace monitoring \
  -f monitoring/postgres-exporter-values.yaml

# App metrics
kubectl apply -f monitoring/app-servicemonitor.yaml

# Logging
helm upgrade --install loki-stack grafana/loki-stack \
  --namespace monitoring \
  -f monitoring/loki-values.yaml

# Dashboards (auto-loaded by Grafana's sidecar)
kubectl apply -f monitoring/dashboards/infra-overview-dashboard.yaml
kubectl apply -f monitoring/dashboards/app-overview-dashboard.yaml
```

Full details and rationale: [`monitoring/README.md`](monitoring/README.md).

### 8. Access services

```bash
# From local machine, tunnel through the bastion:
ssh -i jumphost.pem -L 8080:localhost:8080 -L 3000:localhost:3000 -L 9090:localhost:9090 ec2-user@<bastion-ip>

# On the bastion, in the same session:
kubectl port-forward svc/sample-app-svc -n devops-assignment 8080:80 &
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &
```

Then open `http://localhost:8080` (app), `http://localhost:3000` (Grafana),
`http://localhost:9090` (Prometheus) locally.

## CI/CD Pipeline (Part 2)

`.github/workflows/ci-cd.yml` runs on every PR and push:

- **PR to `main`/`dev`**: lint + unit tests (Jest/Supertest), dependency
  vulnerability scan (Trivy).
- **Push to `main`/`dev`**: builds the Docker image, scans it with Trivy,
  pushes to ECR tagged with the commit SHA (immutable tags — no `:latest`,
  see Challenges doc), then deploys to the `devops-assignment` namespace
  (staging).
- **Push to `main` only**: after staging succeeds, `deploy-production` waits
  for manual approval via a GitHub Environment protection rule before
  re-running the same deploy against production.
- Failures at any stage post to Slack via an incoming webhook
  (`SLACK_WEBHOOK_URL` secret).

## Architecture Decisions

- **EKS over ECS/EC2**: chosen to demonstrate Kubernetes orchestration depth
  (managed node groups, IRSA, CSI drivers, HPA) — a heavier but more broadly
  applicable skill set than ECS or static EC2/ASG.
- **Dedicated least-privilege IAM user for CI/CD**: GitHub Actions
  authenticates as a scoped IAM user (ECR push/pull + `eks:DescribeCluster`
  only) with a namespace-scoped EKS access entry (`AmazonEKSEditPolicy`,
  scoped to `devops-assignment`), rather than reusing admin or bastion
  credentials.
- **Immutable ECR tags, commit-SHA based**: the ECR repository enforces tag
  immutability; every build is tagged with the Git commit SHA rather than a
  mutable `:latest`, guaranteeing every deployed image is traceable to an
  exact commit and preventing accidental overwrites.
- **Modular Terraform**: each concern (vpc, security_groups, eks, rds, ecr,
  bastion) is an isolated module with explicit inputs/outputs.
- **Loki over EFK for logging**: much lower resource footprint for this
  cluster size, and integrates directly into the same Grafana instance as
  metrics — one pane of glass for both.

## Security Considerations

- Application-tier resources (EKS nodes, RDS) sit in **private subnets**.
- RDS storage is encrypted at rest; not publicly accessible.
- Database credentials are never committed to source control — generated/
  supplied at deploy time and injected via Kubernetes Secrets.
- CI/CD uses a dedicated IAM user scoped to only the permissions it needs
  (ECR push/pull, EKS namespace-level access) rather than broad admin
  credentials in GitHub Secrets.
- EKS cluster uses IAM Roles for Service Accounts (IRSA) via an OIDC
  provider for the EBS CSI driver, rather than broad node-level IAM
  permissions.
- Grafana admin credentials and the RDS connection string used by the
  Postgres exporter are stored as Kubernetes Secrets, never inlined in
  Helm values files.
- `jumphost.pem` and `terraform.tfvars` are excluded via `.gitignore` and
  were never committed.

## Cost Optimization

- NAT Gateway is toggleable via `enable_nat_gateway` variable.
- ECR lifecycle policy retains only a bounded number of recent images.
- Prometheus/Loki retention explicitly bounded (15d / 14d) rather than left
  at chart defaults, to cap EBS storage cost.
- All resources are destroyable via `terraform destroy` — recommended
  immediately after grading/demo to stop billing.

## Repository Structure

```
.
├── Screenshots/           # Evidence: part1-infra, part2-pipeline, part3-monitoring
├── terraform/
│   ├── backend.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── variable.tf
│   └── modules/
│       ├── bastion/
│       ├── ecr/
│       ├── eks/
│       ├── rds/
│       ├── security_groups/
│       └── vpc/
├── app/                   # Sample Node.js/Express app (RDS-connected)
│   ├── index.js
│   ├── index.test.js
│   ├── package.json
│   └── Dockerfile
├── manifests/             # Kubernetes manifests
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── hpa.yaml
├── monitoring/            # Prometheus/Grafana/Loki Helm values, dashboards, alert rules
│   ├── prometheus-values.yaml
│   ├── prometheus-rules.yaml
│   ├── postgres-exporter-values.yaml
│   ├── app-servicemonitor.yaml
│   ├── loki-values.yaml
│   ├── commands.sh
│   ├── dashboards/
│   └── scripts/
├── .github/workflows/     # CI/CD pipeline (ci-cd.yml)
├── .yamllint.yml
├── .gitignore
├── README.md              # this file
├── APPROACH.md            # design rationale for each part
└── CHALLENGES.pdf         # issues hit and how each was resolved
```

## Documentation

- [`APPROACH.md`](APPROACH.md) — why each major decision was made (EKS vs.
  ECS, Loki vs. EFK, IAM/IRSA design, etc.)
- [`CHALLENGES.pdf`](CHALLENGES.pdf) — the real technical obstacles hit while
  building this (exact error messages, diagnosis steps, and fixes), including
  the AWS account restriction on load balancer creation that's the reason the
  access instructions above use `kubectl port-forward` rather than a public
  URL (see Challenge #7 in that document).

## Evidence / Screenshots

The [`Screenshots/`](Screenshots/) folder contains proof of each part
actually running, organized by part:

- **`Screenshots/part1-infra/`** — Terraform apply output, AWS Console views
  of the provisioned VPC, EKS cluster, and RDS instance.
- **`Screenshots/part2-pipeline/`** — GitHub Actions pipeline runs (tests
  passing on PR, image build/push to ECR, staging deployment, production
  approval gate).
- **`Screenshots/part3-monitoring/`** — Grafana dashboards (Infrastructure
  Overview and Application & Database Overview) showing live data, and
  Prometheus targets/alerts.