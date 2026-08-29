#!/usr/bin/env bash
# Run from the bastion, with kubectl already pointed at the EKS cluster.
# Assumes: kubectl, helm v3 installed; AWS credentials/role available for
# the RDS secret step.
set -euo pipefail

# ---------- 0. namespace ----------
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# ---------- 1. add helm repos ----------
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ---------- 2. Grafana admin password: generate + store as k8s Secret ----------
# never hardcode this in values.yaml / never commit it to git
GRAFANA_ADMIN_PASSWORD=$(openssl rand -base64 18)
kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
echo "Grafana admin password (save this now, it won't be printed again): ${GRAFANA_ADMIN_PASSWORD}"

# ---------- 3. kube-prometheus-stack (Prometheus + Alertmanager + Grafana + exporters) ----------
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f prometheus-values.yaml \
  --set grafana.admin.existingSecret=grafana-admin-credentials \
  --set grafana.admin.userKey=admin-user \
  --set grafana.admin.passwordKey=admin-password

kubectl apply -f prometheus-rules.yaml

# ---------- 4. Postgres (RDS) exporter ----------
# Build the DSN and store it as a Secret; RDS creds should come from
# Secrets Manager / SSM Parameter Store in real usage, not typed here.
RDS_ENDPOINT="<rds-endpoint>:5432"
RDS_USER="<readonly-monitoring-user>"
RDS_PASSWORD="<from-secrets-manager>"
RDS_DB="postgres"

kubectl create secret generic rds-postgres-exporter-secret \
  --namespace monitoring \
  --from-literal=data-source-name="postgresql://${RDS_USER}:${RDS_PASSWORD}@${RDS_ENDPOINT}/${RDS_DB}?sslmode=require" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
  --namespace monitoring \
  -f postgres-exporter-values.yaml

# ---------- 5. app ServiceMonitor ----------
kubectl apply -f app-servicemonitor.yaml

# ---------- 6. centralized logging: Loki + Promtail ----------
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki-stack grafana/loki-stack \
  --namespace monitoring \
  -f loki-values.yaml

# ---------- 7. dashboards (auto-loaded by Grafana sidecar via label) ----------
kubectl apply -f dashboards/infra-overview-dashboard.yaml
kubectl apply -f dashboards/app-overview-dashboard.yaml

# ---------- 8. sanity checks ----------
kubectl get pods -n monitoring
echo "Port-forward Grafana to check locally:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "Then browse http://localhost:3000 (user: admin, password: printed above)."
echo "In production this should sit behind the ALB Ingress from Part 1 with TLS, not port-forward."