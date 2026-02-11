#!/usr/bin/env bash
set -euo pipefail

# ---- Variables à exporter avant d’exécuter ce script ----
# export JENKINS_ADMIN_PASSWORD="..."
# export SONAR_TOKEN="..."
# export JENKINS_PUBLIC_IP="3.88.129.182"  (ou auto-detect)
# ---------------------------------------------------------

echo "[0/10] Fix Jenkins apt repo GPG (must be before apt update)..."

sudo rm -f /etc/apt/sources.list.d/jenkins.list
sudo rm -f /usr/share/keyrings/jenkins-keyring.asc
sudo rm -f /usr/share/keyrings/jenkins-keyring.gpg
sudo rm -f /etc/apt/keyrings/jenkins.gpg

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/jenkins.gpg

sudo chmod a+r /etc/apt/keyrings/jenkins.gpg

echo "deb [signed-by=/etc/apt/keyrings/jenkins.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null
  
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

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/jenkins.gpg

sudo chmod a+r /etc/apt/keyrings/jenkins.gpg

echo "deb [signed-by=/etc/apt/keyrings/jenkins.gpg] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list >/dev/null

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

echo "[8/10] Install Jenkins plugins (jenkins-plugin-cli)..."
# jenkins-plugin-cli est fourni dans les versions récentes ; sinon on le télécharge
if ! command -v jenkins-plugin-cli >/dev/null 2>&1; then
  echo "Downloading jenkins-plugin-cli..."
  curl -fsSL -o /tmp/jenkins-plugin-cli.jar \
    https://github.com/jenkinsci/plugin-installation-manager-tool/releases/latest/download/jenkins-plugin-manager.jar
  sudo install -d /usr/local/lib/jenkins
  sudo mv /tmp/jenkins-plugin-cli.jar /usr/local/lib/jenkins/jenkins-plugin-cli.jar
  cat <<'EOF' | sudo tee /usr/local/bin/jenkins-plugin-cli >/dev/null
#!/usr/bin/env bash
java -jar /usr/local/lib/jenkins/jenkins-plugin-cli.jar "$@"
EOF
  sudo chmod +x /usr/local/bin/jenkins-plugin-cli
fi

sudo -u jenkins jenkins-plugin-cli --plugin-file ./jenkins/plugins/plugins.txt

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