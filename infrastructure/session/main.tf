module "network" {
  source             = "../modules/network"
  availability_zones = var.availability_zones
}

module "eks" {
  source                    = "../modules/eks"
  name                      = var.name
  account_id                = var.account_id
  region                    = var.region
  operator_cidrs            = var.operator_cidrs
  operator_role_arn         = var.operator_role_arn
  kubernetes_version        = var.kubernetes_version
  instance_type             = var.instance_type
  public_subnet_ids         = module.network.public_subnet_ids
  load_balancer_policy_json = file("${path.module}/policies/load-balancer.json")
}

module "data" {
  source                    = "../modules/data"
  name                      = var.name
  account_id                = var.account_id
  region                    = var.region
  availability_zones        = var.availability_zones
  budget_email              = var.budget_email
  existing_backup_snapshot  = var.existing_backup_snapshot
  vpc_id                    = module.network.vpc_id
  database_subnet_ids       = module.network.database_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
  cluster_name              = module.eks.cluster_name
}
