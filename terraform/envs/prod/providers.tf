provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-eks-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
    }
  }
}

# Cluster credentials are short-lived tokens minted from the caller's AWS
# identity. No kubeconfig is stored in state or in the repository.
data "aws_eks_cluster_auth" "this" {
  name = module.platform.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = module.platform.cluster_endpoint
    cluster_ca_certificate = base64decode(module.platform.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
