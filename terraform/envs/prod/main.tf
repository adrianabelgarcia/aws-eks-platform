# Thin environment root. All logic lives in modules/platform; this root only
# supplies the environment's variables (terraform.tfvars) and providers.

module "platform" {
  source = "../../modules/platform"

  environment                = var.environment
  region                     = var.region
  cluster_name               = var.cluster_name
  kubernetes_version         = var.kubernetes_version
  vpc_cidr                   = var.vpc_cidr
  availability_zones         = var.availability_zones
  nat_strategy               = var.nat_strategy
  public_access_cidrs        = var.public_access_cidrs
  platform_admin_role_arn    = var.platform_admin_role_arn
  terraform_role_arn         = var.terraform_role_arn
  auditor_role_arn           = var.auditor_role_arn
  hosted_zone_arns           = var.hosted_zone_arns
  log_retention_days         = var.log_retention_days
  deletion_protection        = var.deletion_protection
  system_node_instance_types = var.system_node_instance_types
  system_node_min_size       = var.system_node_min_size
  system_node_desired_size   = var.system_node_desired_size
  system_node_max_size       = var.system_node_max_size
  karpenter_replicas         = var.karpenter_replicas
  argocd_ha                  = var.argocd_ha
  gitops_repo_url            = var.gitops_repo_url
  gitops_revision            = var.gitops_revision
}
