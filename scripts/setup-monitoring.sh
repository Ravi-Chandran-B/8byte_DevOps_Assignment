#!/bin/bash
# Run this manually on the bastion AFTER terraform apply has completed
# and the EKS cluster/node group are healthy (kubectl get nodes shows Ready).
#
# This is intentionally NOT part of user_data.sh.tpl — it depends on the
# EKS cluster, RDS instance, and Secrets Manager secret all being fully
# provisioned first, which can't be guaranteed at bastion boot time.
#
# Usage:
#   chmod +x setup-monitoring.sh
#   ./setup-monitoring.sh

set -euo pipefail

echo "==> Adding Helm repos"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo "==> Creating monitoring namespace"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing kube-prometheus-stack (Prometheus + Grafana + Alertmanager)"
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/monitoring/prometheus-values.yaml \
  --wait --timeout 15m

echo "==> Grafana admin credentials:"
echo -n "  username: "
kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath="{.data.admin-user}" | base64 --decode; echo
echo -n "  password: "
kubectl get secret grafana-admin-credentials -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode; echo

echo "==> Ensuring jq is installed"
sudo dnf install -y jq

echo "==> Creating application namespace"
kubectl create namespace devops-assignment --dry-run=client -o yaml | kubectl apply -f -

echo "==> Pulling DB credentials from Secrets Manager"
secret=$(aws secretsmanager get-secret-value \
  --secret-id devops-assignment/rds/credentials \
  --region us-east-1 \
  --query SecretString --output text)

echo "==> Creating rds-credentials K8s secret"
kubectl create secret generic rds-credentials \
  --namespace devops-assignment \
  --from-literal=host=$(echo "$secret" | jq -r .host) \
  --from-literal=dbname=$(echo "$secret" | jq -r .dbname) \
  --from-literal=username=$(echo "$secret" | jq -r .username) \
  --from-literal=password=$(echo "$secret" | jq -r .password) \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Deploying application"
kubectl apply -f ~/manifests/01-deployment.yaml
kubectl apply -f ~/manifests/02-service.yaml
kubectl apply -f ~/manifests/03-hpa.yaml

echo "==> Done. Verifying:"
kubectl get pods -n monitoring
kubectl get pods -n devops-assignment