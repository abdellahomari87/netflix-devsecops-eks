#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"
RELEASE="monitoring"

echo "[1/6] Checking kubectl connectivity..."
kubectl get nodes >/dev/null

echo "[2/6] Checking helm..."
if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm not found. Install Helm first."
  exit 1
fi

echo "[3/6] Adding prometheus-community repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "[4/6] Creating namespace (if needed)..."
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${NAMESPACE}"

echo "[5/6] Installing/Upgrading kube-prometheus-stack..."
helm upgrade --install "${RELEASE}" prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --wait

echo "[6/6] Done."
kubectl -n "${NAMESPACE}" get pods
kubectl -n "${NAMESPACE}" get svc