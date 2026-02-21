#!/usr/bin/env bash
set -e

echo "Configuring SonarQube webhook..."

SONAR_URL="http://localhost:9000"
JENKINS_URL="http://${JENKINS_PUBLIC_IP}:8080"

# attendre que Sonar soit prêt
echo "Waiting for SonarQube..."
until curl -s "$SONAR_URL/api/system/status" | grep -q '"status":"UP"'; do
  sleep 5
done

curl -u "${SONAR_TOKEN}:" \
  -X POST "${SONAR_URL}/api/webhooks/create" \
  -d "name=jenkins" \
  -d "url=${JENKINS_URL}/sonarqube-webhook/" || true

echo "Webhook configured"
