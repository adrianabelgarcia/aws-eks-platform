locals {
  cluster_admin_policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  view_policy_arn          = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  # Only platform components with explicit tolerations are allowed on the
  # tainted system node group. Everything else lands on Karpenter capacity.
  system_toleration = {
    key      = "CriticalAddonsOnly"
    operator = "Exists"
    effect   = "NoSchedule"
  }
}

module "eks" {
  #checkov:skip=CKV_TF_1: Terraform Registry module pinned to an exact minor range and recorded in .terraform.lock.hcl. Commit-hash pinning applies to git sources; upgrades flow through Dependabot.
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name               = var.name
  kubernetes_version = var.kubernetes_version
  upgrade_policy = {
    support_type = var.support_type
  }
  deletion_protection = var.deletion_protection

  # Access entries replace the legacy aws-auth ConfigMap. Authorization is
  # managed through IAM and is auditable in CloudTrail.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = {
    platform_admins = {
      principal_arn = var.platform_admin_role_arn
      policy_associations = {
        cluster_admin = {
          policy_arn   = local.cluster_admin_policy_arn
          access_scope = { type = "cluster" }
        }
      }
    }
    terraform_deployer = {
      principal_arn = var.terraform_role_arn
      policy_associations = {
        cluster_admin = {
          policy_arn   = local.cluster_admin_policy_arn
          access_scope = { type = "cluster" }
        }
      }
    }
    read_only_auditors = {
      principal_arn = var.auditor_role_arn
      policy_associations = {
        view = {
          policy_arn   = local.view_policy_arn
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = var.subnet_ids

  # Private endpoint for in-VPC traffic (nodes, Karpenter, Argo CD). Public
  # endpoint stays on only for the CIDRs listed, which covers the CI runners
  # and operator VPN egress. Never 0.0.0.0/0; enforced by variable validation.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs

  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = var.log_kms_key_arn

  # Envelope encryption of Kubernetes Secrets with a customer managed key.
  create_kms_key          = true
  enable_kms_key_rotation = true
  kms_key_administrators  = [var.platform_admin_role_arn]
  encryption_config = {
    resources = ["secrets"]
  }

  # Karpenter discovers node security groups by this tag.
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.name
  }

  addons = {
    # Versions are the default for the cluster's Kubernetes version rather
    # than the newest release, so two plans on the same day produce the same
    # addon versions. Upgrades are explicit changes in git.
    coredns = {
      most_recent = false
      configuration_values = jsonencode({
        tolerations  = [local.system_toleration]
        nodeSelector = { "node-role" = "system" }
      })
    }
    kube-proxy = {
      most_recent = false
    }
    vpc-cni = {
      most_recent    = false
      before_compute = true
      configuration_values = jsonencode({
        env = {
          # Prefix delegation gives each node /28 blocks instead of single
          # IPs, which removes the classic ENI/IP ceiling on pod density.
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = {
      most_recent    = false
      before_compute = true
    }
    aws-ebs-csi-driver = {
      most_recent = false
    }
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "BOTTLEROCKET_ARM_64"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"
      min_size       = var.system_node_min_size
      desired_size   = var.system_node_desired_size
      max_size       = var.system_node_max_size

      labels = {
        "node-role" = "system"
      }

      # Only critical platform addons tolerate this taint. Application
      # workloads never schedule here, so a noisy neighbour cannot starve
      # CoreDNS or the Karpenter controller.
      taints = {
        critical_addons = {
          key    = local.system_toleration.key
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }

      # IMDSv2 required, hop limit 1: pods cannot reach the node role's
      # instance credentials. Workloads authenticate through EKS Pod Identity.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 1
      }

      block_device_mappings = {
        data = {
          device_name = "/dev/xvdb"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      update_config = {
        max_unavailable_percentage = 33
      }
    }
  }
}
