variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used for tagging and resource naming"
  type        = string
  default     = "devops-assignment"
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

# ---------- VPC ----------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "enable_nat_gateway" {
  description = "Whether to create a NAT Gateway (costs money/hr). Set false to save cost; private instances then have no outbound internet."
  type        = bool
  default     = true
}

# ---------- EKS ----------
variable "cluster_version" {
  description = "Kubernetes version for EKS control plane"
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group (t3.micro is too small for EKS nodes)"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# ---------- Bastion ----------
variable "bastion_instance_type" {
  description = "Instance type for the bastion host (t3.micro is free tier)"
  type        = string
  default     = "t3.micro"
}

variable "bastion_key_pair_name" {
  description = "Name of an EXISTING EC2 key pair (create it first) for SSH into the bastion"
  type        = string
}

variable "bastion_allowed_ssh_cidr" {
  description = "Your IP in CIDR form, e.g. \"49.207.xx.xx/32\". Find it via: curl ifconfig.me"
  type        = string
}

# ---------- RDS ----------
variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.3"
}

variable "db_instance_class" {
  description = "RDS instance class (keep db.t3.micro/db.t4g.micro for free tier)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Storage in GB (free tier covers up to 20GB)"
  type        = number
  default     = 20
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "db_multi_az" {
  description = "Multi-AZ RDS (NOT free tier — keep false for this assignment)"
  type        = bool
  default     = false
}


variable "app_port" {
  description = "Port the application listens on"
  type        = number
  default     = 80
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository for the application image"
  type        = string
  default     = "digital-app"
}