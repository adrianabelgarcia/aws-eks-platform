# ADR-0002: EKS Pod Identity over IRSA

- Status: Accepted
- Date: 2026-11-13
- Deciders: Platform team

## Context and Problem Statement

Pods need AWS permissions (load balancer controller, ExternalDNS, EBS CSI,
Karpenter). Two mechanisms exist in EKS: IAM Roles for Service Accounts (IRSA),
which uses an OIDC provider and a service account annotation, and EKS Pod Identity,
which uses the EKS Pod Identity Agent and a Pod Identity association.

## Decision Drivers

- Least privilege per workload, without sharing roles across controllers
- Operational simplicity when creating roles across many clusters
- Trust policy hygiene: IRSA trust policies embed the cluster's OIDC issuer URL
- Support for role chaining and cross-account access
- Compatibility with third-party charts that expect IRSA annotations

## Considered Options

1. IRSA for every workload
2. EKS Pod Identity for every workload
3. Node IAM role with broad permissions (rejected outright)

## Decision Outcome

Chosen option: **EKS Pod Identity** for all platform workloads and all future
application workloads.

Each controller gets its own IAM role through the `terraform-aws-modules/eks-pod-identity`
module, with the managed policy that controller needs. Each role is bound to exactly
one namespace and service account through an `aws_eks_pod_identity_association`.
Trust policies are generic (`pods.eks.amazonaws.com`), so they do not depend on the
cluster's OIDC issuer and can be reused when a cluster is rebuilt.

Node IAM roles carry only the managed policies a node needs to join the cluster and
pull images. Instance metadata is restricted to hop limit 1, so a pod cannot read the
node role's credentials from IMDS.

The EKS OIDC provider stays in place for third-party charts that still require IRSA.

### Consequences

- Positive: Roles are not tied to an OIDC issuer, which makes cluster rebuilds simpler.
- Positive: The association is an explicit, auditable object in AWS, separate from the
  Kubernetes service account.
- Positive: Pod Identity also works without annotating service accounts, so manifests
  in git stay free of account IDs.
- Negative: The Pod Identity Agent is a DaemonSet that must be healthy for credentials
  to be issued. It is an EKS managed addon and is installed before compute.
- Negative: Some charts still document IRSA only. Each such chart needs a conscious
  decision, and the OIDC provider has to remain available for them.
- Negative: Pod Identity does not cover Fargate workloads the same way. None are
  planned.

## Pros and Cons of the Options

### IRSA

- Good: Universally supported, including by older charts.
- Good: Works across clusters with the same OIDC issuer model.
- Bad: Trust policies embed the OIDC provider URL, which couples roles to one cluster.
- Bad: Requires service account annotations, which leak account IDs into manifests.

### EKS Pod Identity

- Good: Decoupled trust, no service account annotation, explicit association objects.
- Good: Terraform support is first class through the eks-pod-identity module.
- Bad: Requires the Pod Identity Agent addon, and some third-party charts do not yet
  document it.

### Node IAM role with broad permissions

- Rejected: Every pod on the node inherits the permissions. This is a privilege
  escalation path and fails any least-privilege review.
