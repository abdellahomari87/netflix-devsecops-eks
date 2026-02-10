#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"
RELEASE="monitoring"

echo "[1/3] Uninstalling helm release..."
helm -n "${NAMESPACE}" uninstall "${RELEASE}" || true

echo "[2/3] Deleting namespace..."
kubectl delete ns "${NAMESPACE}" --wait || true

echo "[3/3] Done."