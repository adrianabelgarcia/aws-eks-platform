output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs. EKS nodes, Karpenter nodes and the control plane ENIs live here."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs. Only internet-facing load balancers are placed here."
  value       = module.vpc.public_subnets
}

output "availability_zones" {
  description = "Availability zones used by the VPC."
  value       = local.azs
}
