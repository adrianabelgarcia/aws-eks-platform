locals {
  system_node_placement = {
    nodeSelector = { "node-role" = "system" }
    tolerations = [{
      key      = "CriticalAddonsOnly"
      operator = "Exists"
      effect   = "NoSchedule"
    }]
  }
  root_path = "gitops/clusters/${var.environment}"
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  wait             = true

  values = [
    yamlencode({
      global = local.system_node_placement

      configs = {
        cm = {
          # Annotation-based tracking avoids label collisions with the
          # Kubernetes and Helm labels that workloads already carry.
          "application.resourceTrackingMethod" = "annotation"
          "timeout.reconciliation"             = "180s"
        }
      }

      # Human SSO is wired in a later change; until then Dex stays off and
      # admin access goes through the Kubernetes API.
      dex = {
        enabled = false
      }

      server = {
        replicas = var.ha ? 2 : 1
      }
      repoServer = {
        replicas = var.ha ? 2 : 1
      }
    })
  ]
}

# Root of the app-of-apps. Terraform creates it once; from then on Argo CD
# reconciles everything under gitops/clusters/<env> from git.
resource "helm_release" "argocd_root" {
  name       = "argocd-root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  wait       = false

  values = [
    yamlencode({
      applications = {
        root = {
          namespace  = "argocd"
          project    = "default"
          finalizers = ["resources-finalizer.argocd.argoproj.io"]
          source = {
            repoURL        = var.gitops_repo_url
            targetRevision = var.gitops_revision
            path           = local.root_path
            directory = {
              recurse = false
            }
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
          }
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}
