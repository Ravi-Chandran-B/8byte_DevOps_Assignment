#!/bin/bash
set -euo pipefail

dnf update -y

# ---------- AWS CLI v2 ----------
dnf install -y unzip tar gzip
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update

# ---------- kubectl ----------
KUBECTL_VERSION=$(curl -Ls https://dl.k8s.io/release/stable.txt)
curl -Ls -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# ---------- Helm ----------
curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ---------- Configure kubeconfig ----------
sudo -u ec2-user aws eks update-kubeconfig \
  --name ${eks_cluster_name} \
  --region ${aws_region}

echo "Bastion setup complete." >> /var/log/bastion-setup.log