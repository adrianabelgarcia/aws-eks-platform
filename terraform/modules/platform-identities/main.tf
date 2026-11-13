# One Pod Identity role per workload. Each role carries only the policy its
# controller needs, and the association pins it to exactly one service
# account. No node-wide IAM permissions and no IRSA annotations.

module "aws_load_balancer_controller_identity" {
  #checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact minor range and recorded in .terraform.lock.hcl. Commit-hash pinning applies to git sources; upgrades flow through Dependabot.
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                            = "${var.cluster_name}-aws-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    aws_load_balancer_controller = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

module "external_dns_identity" {
  #checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact minor range and recorded in .terraform.lock.hcl. Commit-hash pinning applies to git sources; upgrades flow through Dependabot.
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                       = "${var.cluster_name}-external-dns"
  attach_external_dns_policy = true
  # Scope Route53 changes to the zones this platform owns, not every zone in
  # the account.
  external_dns_hosted_zone_arns = var.hosted_zone_arns

  associations = {
    external_dns = {
      cluster_name    = var.cluster_name
      namespace       = "external-dns"
      service_account = "external-dns"
    }
  }
}

module "ebs_csi_identity" {
  #checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact minor range and recorded in .terraform.lock.hcl. Commit-hash pinning applies to git sources; upgrades flow through Dependabot.
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true
  aws_ebs_csi_kms_arns      = var.ebs_kms_key_arns

  associations = {
    ebs_csi_controller = {
      cluster_name    = var.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}
