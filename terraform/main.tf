module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
  enable_nat_gateway   = var.enable_nat_gateway
}

module "security_groups" {
  source = "./modules/security_groups"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  app_port     = var.app_port
}

module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  cluster_version     = var.cluster_version
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  ec2_sg_id           = module.security_groups.ec2_sg_id
  bastion_role_arn    = module.bastion.bastion_role_arn
  bastion_sg_id       = module.bastion.bastion_sg_id
  rds_sg_id           = module.security_groups.rds_sg_id
}

module "bastion" {
  source = "./modules/bastion"

  project_name     = var.project_name
  vpc_id           = module.vpc.vpc_id
  public_subnet_id = module.vpc.public_subnet_ids[0]
  instance_type    = var.bastion_instance_type
  key_pair_name    = var.bastion_key_pair_name
  allowed_ssh_cidr = var.bastion_allowed_ssh_cidr
  eks_cluster_name = "${var.project_name}-eks"
}

module "rds" {
  source = "./modules/rds"

  project_name         = var.project_name
  private_subnet_ids   = module.vpc.private_subnet_ids
  rds_sg_id            = module.security_groups.rds_sg_id
  db_engine_version    = var.db_engine_version
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_name              = var.db_name
  db_username          = var.db_username
  db_multi_az          = var.db_multi_az
}

module "ecr" {
  source = "./modules/ecr"

  project_name    = var.project_name
  repository_name = var.ecr_repository_name
}