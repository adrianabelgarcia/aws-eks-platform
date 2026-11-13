# Architecture

This document describes how the platform is laid out and why. Decisions with
trade-offs are recorded in [`adr/`](adr/); operational procedures are in
[`runbooks/`](runbooks/); service objectives are in [`slo.md`](slo.md).

## 1. Network

Each environment gets its own VPC. Three availability zones, a `/20` private
subnet per zone for nodes and pods (large enough for prefix-delegated VPC CNI),
and a `/24` public subnet per zone that holds only internet-facing load balancers
and NAT gateways.

```mermaid
flowchart TB
  internet((Internet)) --> igw["Internet Gateway"]

  subgraph vpc["VPC /16 (one per environment)"]
    direction TB
    subgraph public["Public subnets (/24 per AZ)"]
      alb["ALB (sample-api ingress)"]
      nat["NAT gateway(s)<br/>staging: 1 · prod: 1 per AZ"]
    end
    subgraph private["Private subnets (/20 per AZ)"]
      sys["System managed node group<br/>tainted CriticalAddonsOnly"]
      karp["Karpenter-managed nodes<br/>Bottlerocket"]
      cp["EKS control plane ENIs"]
    end
    s3gw["S3 gateway endpoint"]
    flow["VPC flow logs<br/>CloudWatch, KMS-encrypted"]
  end

  igw --> alb
  alb -->|"IP targets"| karp
  karp --> nat --> igw
  sys --> nat
  karp --> s3gw
  sys --> s3gw
  vpc -.-> flow
```

Design points:

- Nodes never receive public IPs. Egress goes through NAT, and S3 traffic stays
  on the gateway endpoint so it bypasses NAT data charges.
- Default security group is emptied. Every security group is explicit.
- Subnets carry `karpenter.sh/discovery` and the `kubernetes.io/role/*-elb` tags,
  so Karpenter and the load balancer controller place resources without hard-coded IDs.

## 2. Cluster

```mermaid
flowchart LR
  subgraph cp["EKS control plane"]
    api["API server<br/>private endpoint + public endpoint<br/>restricted to allowed CIDRs"]
    kms[("KMS key<br/>Secrets envelope encryption")]
    logs[("Control plane logs<br/>api, audit, authenticator,<br/>controllerManager, scheduler")]
  end

  subgraph sys["System managed node group (Bottlerocket arm64, On-Demand)"]
    coredns["CoreDNS"]
    cni["VPC CNI (prefix delegation)"]
    pia["EKS Pod Identity Agent"]
    karpctl["Karpenter controller"]
    argo["Argo CD"]
    lbc["AWS Load Balancer Controller"]
    edns["ExternalDNS"]
    kyv["Kyverno"]
    prom["kube-prometheus-stack"]
  end

  subgraph dyn["Karpenter capacity"]
    gen["NodePool general<br/>Spot preferred, On-Demand fallback"]
    base["NodePool baseline<br/>On-Demand only"]
  end

  karpctl -->|"provisions via EC2 Fleet"| dyn
  sqs[("SQS interruption queue")] --> karpctl
  eb["EventBridge rules<br/>Spot interruption, rebalance,<br/>instance state, scheduled change"] --> sqs

  api --- kms
  api --- logs
  pia -.->|"Pod Identity credentials"| lbc
  pia -.-> edns
  pia -.-> karpctl
```

Access control has no `aws-auth` ConfigMap. Humans, the CI Terraform role and an
auditor role are granted through EKS access entries backed by AWS managed access
policies. Workloads authenticate to AWS through EKS Pod Identity, one role per
controller, scoped to the minimum policy it needs.

## 3. GitOps flow

Terraform installs Argo CD and one root `Application`. Everything after that is
pulled from git. Nothing in the cluster is changed by a pipeline pushing manifests.

```mermaid
sequenceDiagram
  autonumber
  actor Dev as Engineer
  participant GH as GitHub (aws-eks-platform)
  participant CI as GitHub Actions
  participant TF as Terraform (CI role)
  participant Argo as Argo CD (in cluster)
  participant K8s as Kubernetes API

  Dev->>GH: Pull request
  GH->>CI: gitops.yml: yamllint, kustomize, kubeconform, kyverno
  GH->>CI: terraform.yml: fmt, validate, tflint, checkov, plan
  CI-->>GH: Status checks
  GH-->>Dev: Review and merge to main

  Note over TF,K8s: One-time per cluster
  TF->>K8s: Install Argo CD and Karpenter (Helm)
  TF->>K8s: Create root Application (gitops/clusters/<env>)

  loop Every reconciliation
    Argo->>GH: Fetch main
    Argo->>K8s: Sync AppProject (wave -10)
    Argo->>K8s: Sync platform apps (wave 0)
    Argo->>K8s: Sync policies and NodePools (wave 5)
    Argo->>K8s: Sync SLO rules (wave 10)
    Argo->>K8s: Sync sample-api (wave 20)
  end
```

Sync waves order the platform so that CRDs (Kyverno, Prometheus Operator, Karpenter)
exist before the resources that depend on them.

## 4. Workload path

```mermaid
flowchart LR
  user["Client"] -->|"HTTPS :443"| r53["Route53<br/>ExternalDNS record"]
  r53 --> alb["ALB<br/>ACM certificate, TLS 1.2+"]
  alb -->|"target-type ip"| pod["sample-api pods<br/>restricted PSA, probes,<br/>PDB, HPA, zone spread"]
  pod -->|"metrics /metrics"| prom["Prometheus"]
  prom --> rules["SLO recording rules<br/>multi-window burn rate"]
  rules --> alerts["Alertmanager<br/>page / ticket"]
```

## 5. Environment differences

| Concern | Staging | Prod |
|---|---|---|
| NAT | single gateway | one gateway per AZ |
| General capacity | Spot preferred, On-Demand fallback | Spot opt-in only |
| Baseline capacity | small On-Demand fallback | On-Demand default landing pool |
| Karpenter replicas | 1 | 2 |
| Argo CD | single replica | HA (2 server, 2 repo-server) |
| Kyverno admission | 2 replicas | 3 replicas |
| Deletion protection | off | on |
| Disruption budgets | 20% | 10% plus no voluntary disruption on weekday US Eastern business hours |

The environment roots are identical. Only `terraform.tfvars`, `backend.hcl` and the
matching `gitops/clusters/<env>` and overlay directories differ.
