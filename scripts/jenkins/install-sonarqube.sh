#!/usr/bin/env bash
set -euo pipefail

CURRENT_USER="${SUDO_USER:-$(id -un)}"

echo "[1/5] Installing Docker if needed..."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io
fi
sudo systemctl enable --now docker

echo "[2/5] Allowing current user to use docker..."
sudo usermod -aG docker "$CURRENT_USER" || true

# IMPORTANT: Le groupe docker ne s'applique qu'à la prochaine session.
# On ne fait PAS chmod 666 sur le socket Docker (mauvaise pratique).
if [ "$CURRENT_USER" = "$(id -un)" ]; then
  # Si on est interactif, on peut tenter de recharger le groupe.
  # Sinon, l'utilisateur devra se reconnecter (SSM/SSH).
  command -v newgrp >/dev/null 2>&1 && newgrp docker <<'EOF' || true
docker ps >/dev/null 2>&1 || true
EOF
fi

echo "[3/5] Setting vm.max_map_count for SonarQube..."
sudo sysctl -w vm.max_map_count=262144 >/dev/null
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-sonarqube.conf >/dev/null
sudo sysctl --system >/dev/null

echo "[4/5] Starting SonarQube (LTS community)..."
if sudo docker ps -a --format '{{.Names}}' | grep -q '^sonar$'; then
  echo "SonarQube container already exists. Restarting..."
  sudo docker restart sonar >/dev/null
else
  sudo docker run -d --name sonar \
    -p 9000:9000 \
    --restart unless-stopped \
    sonarqube:lts-community
fi

echo "[5/5] Done. SonarQube should be available on port 9000."
echo "    Example: http://<EC2_PUBLIC_IP>:9000"