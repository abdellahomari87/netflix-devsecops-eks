#!/usr/bin/env bash
set -euo pipefail

# ---- Variables à exporter avant d’exécuter ce script ----
# export JENKINS_ADMIN_PASSWORD="..."
# export SONAR_TOKEN="..."
# export JENKINS_PUBLIC_IP="3.88.129.182"  (ou auto-detect)
# ---------------------------------------------------------

# Nettoyage Jenkins repo + clés (pour être sûr)
sudo rm -f /etc/apt/sources.list.d/jenkins.list
sudo rm -f /etc/apt/keyrings/jenkins.gpg
sudo rm -f /etc/apt/keyrings/jenkins-keyring.asc
sudo rm -f /usr/share/keyrings/jenkins-keyring.asc
sudo rm -f /etc/apt/trusted.gpg.d/jenkins*.gpg 2>/dev/null || true

sudo install -d -m 0755 /etc/apt/keyrings

# Importer LA clé demandée par APT via keyserver (celle qui finit par 14ABFC68)
sudo gpg --no-default-keyring --keyring /etc/apt/keyrings/jenkins.gpg \
  --keyserver keyserver.ubuntu.com \
  --recv-keys 7198F4B714ABFC68

sudo chmod 0644 /etc/apt/keyrings/jenkins.gpg

# Recréer la source APT Jenkins
echo "deb [signed-by=/etc/apt/keyrings/jenkins.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null

# Vérifier que la clé importée est bien celle attendue
sudo gpg --no-default-keyring --keyring /etc/apt/keyrings/jenkins.gpg --list-keys --fingerprint

# Update (doit être clean)
sudo apt-get update

# ---------------------------------------------------------------------

if [[ -z "${JENKINS_ADMIN_PASSWORD:-}" ]]; then
  echo "ERROR: export JENKINS_ADMIN_PASSWORD first"
  exit 1
fi
if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "ERROR: export SONAR_TOKEN first"
  exit 1
fi

echo "[1/10] Detecting public IP..."
if [[ -z "${JENKINS_PUBLIC_IP:-}" ]]; then
  JENKINS_PUBLIC_IP=$(curl -s ifconfig.me || true)
  export JENKINS_PUBLIC_IP
fi
echo "JENKINS_PUBLIC_IP=${JENKINS_PUBLIC_IP}"

echo "[2/10] apt update + prerequisites..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release unzip jq

echo "[3/10] Install Java Temurin 17..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo tee /etc/apt/keyrings/adoptium.asc >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release && echo $VERSION_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/adoptium.list >/dev/null
sudo apt-get update -y
sudo apt-get install -y temurin-17-jdk

echo "[4/10] Install Jenkins (repo + GPG key)..."

sudo apt-get update -y
sudo apt-get install -y jenkins

echo "[5/10] Install Docker (for pipeline builds + Sonar container)..."
if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get install -y docker.io
  sudo systemctl enable --now docker
fi
sudo usermod -aG docker jenkins || true
sudo chmod 666 /var/run/docker.sock || true

echo "[6/10] Prepare Jenkins directories..."
sudo mkdir -p /var/lib/jenkins/jcasc
sudo chown -R jenkins:jenkins /var/lib/jenkins/jcasc

echo "[7/10] Copy JCasC + plugins list from repo on this machine..."
# On suppose que tu as cloné le repo sur l’EC2 (on le fera via SSM à l’étape 3.5)
if [[ ! -f "./jenkins/jcasc/jenkins.yaml" ]]; then
  echo "ERROR: run this script from the repo root on the EC2 (where ./jenkins/jcasc/jenkins.yaml exists)"
  exit 1
fi
sudo cp -f ./jenkins/jcasc/jenkins.yaml /var/lib/jenkins/jcasc/jenkins.yaml
sudo chown jenkins:jenkins /var/lib/jenkins/jcasc/jenkins.yaml

echo "[8/10] Install Jenkins plugins (offline .hpi download)..."

# On stoppe Jenkins pour éviter les verrous pendant l'install
sudo systemctl stop jenkins || true

# Dossier plugins
sudo install -d -m 0755 -o jenkins -g jenkins /var/lib/jenkins/plugins

# Télécharger chaque plugin listé (un par ligne) depuis updates.jenkins.io
# Format attendu dans plugins.txt: plugin-id ou plugin-id:version
while IFS= read -r p || [[ -n "$p" ]]; do
  # ignore commentaires et lignes vides
  [[ -z "$p" || "$p" =~ ^# ]] && continue

  name="${p%%:*}"
  ver="${p#*:}"
  if [[ "$ver" == "$p" ]]; then ver="latest"; fi

  echo "Installing plugin: $name ($ver)"
  if [[ "$ver" == "latest" ]]; then
    # latest
    curl -fsSL "https://updates.jenkins.io/latest/${name}.hpi" \
      | sudo tee "/var/lib/jenkins/plugins/${name}.jpi" >/dev/null
  else
    # version pin
    curl -fsSL "https://updates.jenkins.io/download/plugins/${name}/${ver}/${name}.hpi" \
      | sudo tee "/var/lib/jenkins/plugins/${name}.jpi" >/dev/null
  fi

  sudo chown jenkins:jenkins "/var/lib/jenkins/plugins/${name}.jpi"
done < ./jenkins/plugins/plugins.txt

# Demander à Jenkins de recharger les plugins
sudo -u jenkins touch /var/lib/jenkins/plugins/.restart-required || true

echo "[9/10] Disable setup wizard + set JCasC env vars..."
# Désactiver le wizard
sudo bash -c 'echo "JAVA_ARGS=\"-Djenkins.install.runSetupWizard=false\"" > /etc/default/jenkins'

# Env vars pour JCasC (systemd override)
sudo mkdir -p /etc/systemd/system/jenkins.service.d
cat <<EOF | sudo tee /etc/systemd/system/jenkins.service.d/override.conf >/dev/null
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/jcasc/jenkins.yaml"
Environment="JENKINS_ADMIN_PASSWORD=${JENKINS_ADMIN_PASSWORD}"
Environment="SONAR_TOKEN=${SONAR_TOKEN}"
Environment="JENKINS_PUBLIC_IP=${JENKINS_PUBLIC_IP}"
EOF

echo "[10/10] Restart Jenkins..."
sudo systemctl daemon-reload
sudo systemctl enable --now jenkins
sudo systemctl restart jenkins

echo "Done."
echo "Jenkins:  http://${JENKINS_PUBLIC_IP}:8080"
echo "Sonar:    http://${JENKINS_PUBLIC_IP}:9000"
