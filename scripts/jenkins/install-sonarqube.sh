#!/usr/bin/env bash
set -euo pipefail

echo "[1/5] Installing Docker if needed..."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi

echo "[2/5] Allowing current user to use docker..."
sudo usermod -aG docker "${USER}" || true
sudo chmod 666 /var/run/docker.sock || true

echo "[3/5] Starting SonarQube (LTS community)..."
# SonarQube recommande vm.max_map_count élevé
echo "[4/5] Setting vm.max_map_count..."
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null
sudo sysctl --system >/dev/null

# Container
if docker ps -a --format '{{.Names}}' | grep -q '^sonar$'; then
  echo "SonarQube container already exists. Restarting..."
  docker restart sonar >/dev/null
else
  docker run -d --name sonar \
    -p 9000:9000 \
    --restart unless-stopped \
    sonarqube:lts-community
fi

echo "[5/5] Done. SonarQube URL: http://$(curl -s ifconfig.me):9000 (or your EC2 public IP)"