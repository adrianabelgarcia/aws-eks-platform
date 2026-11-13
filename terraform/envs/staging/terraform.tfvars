# Staging: single NAT gateway, spot-heavy Karpenter capacity, relaxed deletion
# protection so the environment can be torn down.

environment        = "staging"
region             = "us-east-1"
cluster_name       = "acme-staging"
kubernetes_version = "1.34"
vpc_cidr           = "10.10.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
nat_strategy       = "single"

# TEST-NET-3 documentation range. Replace with the CI runner egress range and
# the operator VPN CIDR before the first apply.
public_access_cidrs = ["203.0.113.0/24"]

platform_admin_role_arn = "arn:aws:iam::111111111111:role/acme-platform-admins"
terraform_role_arn      = "arn:aws:iam::111111111111:role/acme-github-terraform"
auditor_role_arn        = "arn:aws:iam::111111111111:role/acme-platform-auditors"
hosted_zone_arns        = ["arn:aws:route53:::hostedzone/Z00000000STAGING01"]

deletion_protection        = false
log_retention_days         = 365
system_node_instance_types = ["m7g.large"]
system_node_min_size       = 2
system_node_desired_size   = 2
system_node_max_size       = 3
karpenter_replicas         = 1
argocd_ha                  = false

gitops_repo_url = "https://github.com/adrianabelgarcia/aws-eks-platform.git"
gitops_revision = "main"
