locals {
  # Karpenter controller runs on the tainted system node group, never on
  # the capacity it manages.
  system_node_placement = {
    nodeSelector = { "node-role" = "system" }
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  }
}

# Controller IAM (EKS Pod Identity), node IAM role and access entry, SQS
# interruption queue and the EventBridge rules that feed it.
module "karpenter" {
  #checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact minor range and recorded in .terraform.lock.hcl. Commit-hash pinning applies to git sources; upgrades flow through Dependabot.
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.29"

  cluster_name = var.cluster_name

  # Deterministic names: the gitops EC2NodeClass references the node role by
  # name, so it must not carry a random suffix.
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"
  node_iam_role_use_name_prefix = false
  queue_name                    = "${var.cluster_name}-karpenter"

  create_pod_identity_association = true
  namespace                       = "kube-system"
  service_account                 = "karpenter"
  enable_spot_termination         = true
}

# CRDs ship as their own chart so they can be upgraded independently of the
# controller, which is the upstream-recommended layout for Karpenter 1.x.
resource "helm_release" "karpenter_crd" {
  name       = "karpenter-crd"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = var.karpenter_version
  wait       = true
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version
  wait       = true

  values = [
    yamlencode({
      serviceAccount = {
        name = module.karpenter.service_account
      }
      settings = {
        clusterName       = var.cluster_name
        interruptionQueue = module.karpenter.queue_name
      }
      replicas = var.replicas
      controller = {
        # Nodes enforce IMDS hop limit 1, so the controller cannot read its
        # region from instance metadata. Set it explicitly.
        env = [
          { name = "AWS_REGION", value = var.region }
        ]
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { memory = "512Mi" }
        }
      }
      nodeSelector = local.system_node_placement.nodeSelector
      tolerations  = local.system_node_placement.tolerations
    })
  ]

  depends_on = [
    helm_release.karpenter_crd,
    module.karpenter,
  ]
}
