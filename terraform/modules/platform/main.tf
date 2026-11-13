# Composition root for one environment's platform. Environment roots call this
# module once and differ only in their terraform.tfvars.

module "log_key" {
  source = "../log-encryption-key"

  name = var.cluster_name
}

module "network" {
  source = "../network"

  name                    = var.cluster_name
  cluster_name            = var.cluster_name
  cidr                    = var.vpc_cidr
  availability_zones      = var.availability_zones
  nat_strategy            = var.nat_strategy
  log_kms_key_arn         = module.log_key.key_arn
  flow_log_retention_days = var.log_retention_days
}

module "eks" {
  source = "../eks-cluster"

  name                       = var.cluster_name
  kubernetes_version         = var.kubernetes_version
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  public_access_cidrs        = var.public_access_cidrs
  platform_admin_role_arn    = var.platform_admin_role_arn
  terraform_role_arn         = var.terraform_role_arn
  auditor_role_arn           = var.auditor_role_arn
  log_kms_key_arn            = module.log_key.key_arn
  log_retention_days         = var.log_retention_days
  deletion_protection        = var.deletion_protection
  system_node_instance_types = var.system_node_instance_types
  system_node_min_size       = var.system_node_min_size
  system_node_desired_size   = var.system_node_desired_size
  system_node_max_size       = var.system_node_max_size
}

# Each module below waits for the whole EKS module, not just the cluster
# resource. Helm releases must not start until managed nodes and the CoreDNS
# and VPC CNI addons can schedule pods.
module "karpenter" {
  source = "../karpenter"

  cluster_name = module.eks.cluster_name
  region       = var.region
  replicas     = var.karpenter_replicas

  depends_on = [module.eks]
}

module "platform_identities" {
  source = "../platform-identities"

  cluster_name     = module.eks.cluster_name
  hosted_zone_arns = var.hosted_zone_arns

  depends_on = [module.eks]
}

module "gitops" {
  source = "../gitops-bootstrap"

  environment     = var.environment
  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  ha              = var.argocd_ha

  depends_on = [module.karpenter, module.platform_identities]
}
