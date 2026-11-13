data "aws_region" "current" {}

locals {
  azs = var.availability_zones

  # /16 VPC carved into /20 private subnets (large pod IP space for
  # prefix-delegated VPC CNI) and /24 public subnets for ALBs and NAT.
  private_subnets = [for i in range(length(var.availability_zones)) : cidrsubnet(var.cidr, 4, i)]
  public_subnets  = [for i in range(length(var.availability_zones)) : cidrsubnet(var.cidr, 8, 240 + i)]
}

module "vpc" {
  #checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact minor range and recorded in .terraform.lock.hcl. Commit-hash pinning applies to git sources; upgrades flow through Dependabot.
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = false

  enable_nat_gateway     = true
  single_nat_gateway     = var.nat_strategy == "single"
  one_nat_gateway_per_az = var.nat_strategy == "per_az"

  # Lock the default security group down: nothing uses it, and an empty
  # default SG is the safest baseline.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Subnet tags: ELB controller placement and Karpenter subnet discovery.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }

  enable_flow_log                                 = true
  flow_log_max_aggregation_interval               = 60
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days
  flow_log_cloudwatch_log_group_kms_key_id        = var.log_kms_key_arn
}

# Gateway endpoints are free and keep S3 traffic (ECR layers, logs, state
# reads) off the NAT gateways, which is the single biggest data-processing
# cost line in a private EKS network.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids

  tags = {
    Name = "${var.name}-s3"
  }
}
