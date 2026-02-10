1. Architecture

2. One-command deploy


### 1) Provision infra
cd infra/terraform
terraform init
terraform apply

### 2) Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name netflix-devsecops
kubectl get nodes

### 3) Install monitoring (Prometheus + Grafana)
cd ../..
./scripts/install-monitoring.sh

### 4) Access Grafana
./scripts/port-forward-grafana.sh
# open http://localhost:3000


4. Pipeline stages

5. Security & secrets

6. Screenshots