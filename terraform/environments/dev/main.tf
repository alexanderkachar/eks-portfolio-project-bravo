locals {
  cluster_name              = "${var.project_name}-${var.environment}-cluster"
  app_ecr_repository_name   = "${var.project_name}-${var.environment}-app"
  chart_ecr_repository_name = "express-app"
  pat_ssm_parameter_name    = "/${var.project_name}/github/pat"
}

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  cluster_name = local.cluster_name
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

module "ecr" {
  source = "../../modules/ecr"

  project_name     = var.project_name
  environment      = var.environment
  repository_names = [local.app_ecr_repository_name, local.chart_ecr_repository_name]
}

module "eks" {
  source = "../../modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  cluster_name        = local.cluster_name
  cluster_version     = var.cluster_version
  subnet_ids          = module.vpc.private_subnet_ids
  cluster_role_arn    = module.iam.cluster_role_arn
  node_role_arn       = module.iam.node_role_arn
  ebs_csi_role_arn    = module.iam.ebs_csi_role_arn
  admin_principal_arn = var.admin_principal_arn
}

module "runner" {
  source = "../../modules/runner"

  project_name     = var.project_name
  environment      = var.environment
  vpc_id           = module.vpc.vpc_id
  vpc_cidr         = module.vpc.vpc_cidr
  runner_subnet_id = module.vpc.runner_subnet_ids[0]

  github_owner           = var.github_owner
  github_repo            = var.github_repo
  pat_ssm_parameter_name = local.pat_ssm_parameter_name

  ecr_repository_arns = values(module.ecr.repository_arns)

  cluster_name              = module.eks.cluster_name
  cluster_arn               = module.eks.cluster_arn
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "bastion" {
  source = "../../modules/bastion"

  project_name = var.project_name
  environment  = var.environment
  region       = var.region
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  subnet_id = module.vpc.runner_subnet_ids[0]

  cluster_name              = module.eks.cluster_name
  cluster_arn               = module.eks.cluster_arn
  cluster_security_group_id = module.eks.cluster_security_group_id
}
