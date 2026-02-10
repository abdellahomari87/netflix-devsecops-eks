#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"
SECRET_NAME="monitoring-grafana"

echo "[1/3] Getting Grafana admin password..."
PASS=$(kubectl -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath="{.data.admin-password}" | base64 --decode)
echo "Grafana credentials:"
echo "  user: admin"
echo "  pass: ${PASS}"
echo

echo "[2/3] Port-forward Grafana to http://localhost:3000 ..."
echo "Press Ctrl+C to stop."
kubectl -n "${NAMESPACE}" port-forward svc/monitoring-grafana 3000:80