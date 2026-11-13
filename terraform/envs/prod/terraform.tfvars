# Production: NAT gateway per AZ for zonal resilience, on-demand baseline
# capacity via Karpenter, deletion protection on, Argo CD in HA mode.

environment        = "prod"
region             = "us-east-1"
cluster_name       = "acme-prod"
kubernetes_version = "1.34"
vpc_cidr           = "10.20.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
nat_strategy       = "per_az"

# TEST-NET-2 documentation range. Replace with the CI runner egress range and
# the operator VPN CIDR before the first apply.
public_access_cidrs = ["198.51.100.0/24"]

platform_admin_role_arn = "arn:aws:iam::222222222222:role/acme-platform-admins"
terraform_role_arn      = "arn:aws:iam::222222222222:role/acme-github-terraform"
auditor_role_arn        = "arn:aws:iam::222222222222:role/acme-platform-auditors"
hosted_zone_arns        = ["arn:aws:route53:::hostedzone/Z00000000PROD00001"]

deletion_protection        = true
log_retention_days         = 365
system_node_instance_types = ["m7g.large"]
system_node_min_size       = 3
system_node_desired_size   = 3
system_node_max_size       = 5
karpenter_replicas         = 2
argocd_ha                  = true

gitops_repo_url = "https://github.com/adrianabelgarcia/aws-eks-platform.git"
gitops_revision = "main"
