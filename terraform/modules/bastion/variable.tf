variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "Single public subnet to place the bastion in"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "eks_cluster_name" {
  type = string
}

variable "key_pair_name" {
  description = "Existing EC2 key pair name for SSH access to the bastion"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH into the bastion as 0.0.0.0/0."
  type        = string
}