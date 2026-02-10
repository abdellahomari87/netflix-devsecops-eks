variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "netflix-devsecops"
}

variable "eks_version" {
  type    = string
  default = "1.29"
}

variable "key_name" {
  description = "exercice1"
  type        = string
  default     = ""
}

variable "allowed_ssh_cidr" {
  description = " 176.171.104.162/32"
  type        = string
  default     = "0.0.0.0/0"
}