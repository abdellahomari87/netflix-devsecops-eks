provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  name = var.project
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    Project = var.project
    Managed = "terraform"
  }
}

# ---------------------------
# VPC (public + private + NAT)
# ---------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0" # latest (Jan 2026) :contentReference[oaicite:1]{index=1}

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = local.azs
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.tags
}

# ---------------------------
# EKS Cluster
# ---------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.15.1" # latest (Jan 2026) :contentReference[oaicite:2]{index=2}

  name               = local.name
  kubernetes_version = var.eks_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true
  endpoint_public_access_cidrs     = ["176.171.104.162/32"]

  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  # Managed node group (workers)
  eks_managed_node_groups = {
    default = {
      name           = "${local.name}-ng"
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      subnet_ids     = module.vpc.private_subnets
    }
  }

  tags = local.tags
}

# ---------------------------
# IAM Role pour EC2 Jenkins (SSM + accès EKS basique)
# ---------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "jenkins" {
  name               = "${local.name}-jenkins-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Utile plus tard pour pull/push (ECR) si tu choisis ECR au lieu de DockerHub
resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${local.name}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

# ---------------------------
# Security Group Jenkins
# ---------------------------
resource "aws_security_group" "jenkins" {
  name        = "${local.name}-jenkins-sg"
  description = "Jenkins SG"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags

  # Jenkins UI
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SonarQube (on le mettra derrière un reverse proxy plus tard si tu veux)
  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # (Optionnel) Grafana/Prometheus sur l’EC2 si on les met là (sinon monitoring dans EKS)
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH seulement si key_name fourni (sinon utilise SSM Session Manager)
  dynamic "ingress" {
    for_each = var.key_name == "" ? [] : [1]
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_ssh_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------
# EC2 Jenkins (Ubuntu 22.04)
# ---------------------------
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = "t3.medium"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true

  key_name = var.key_name == "" ? null : var.key_name

  tags = merge(local.tags, { Name = "${local.name}-jenkins" })
}