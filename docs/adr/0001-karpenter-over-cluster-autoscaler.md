# ADR-0001: Karpenter over Cluster Autoscaler

- Status: Accepted
- Date: 2026-11-13
- Deciders: Platform team

## Context and Problem Statement

Workloads need capacity that grows and shrinks with demand, mixes Spot and
On-Demand, and does not sit idle. We need a node provisioning mechanism for EKS.
The main options are the Kubernetes Cluster Autoscaler, operating over managed
node groups, and Karpenter, which provisions EC2 instances directly.

## Decision Drivers

- Provisioning latency for pending pods (minutes matter during traffic spikes)
- Cost: Spot usage, instance diversification, and bin-packing
- Operational load: how many node groups must be maintained
- Interruption handling for Spot capacity
- Node lifecycle: forced rotation for OS and kubelet patches

## Considered Options

1. Cluster Autoscaler over several managed node groups, one per instance family
2. Karpenter with NodePools and EC2NodeClass resources
3. Fargate for all workloads

## Decision Outcome

Chosen option: **Karpenter**, for application capacity. A small managed node group
remains for platform controllers (see the architecture document). Its taint
`CriticalAddonsOnly` keeps application pods away from the nodes that run the
controllers Karpenter itself depends on.

Karpenter's `NodePool` objects express the policy in one place:

- `general` prefers Spot and falls back to On-Demand. Requirements are limited to
  current-generation compute and memory families.
- `baseline` is On-Demand only, for workloads that must not be reclaimed.
- `expireAfter` recycles nodes weekly, which rolls out AMI and kubelet changes without
  a manual upgrade.
- Disruption budgets bound how many nodes consolidation can remove at once, and
  prod blocks voluntary disruption during weekday US Eastern business hours.

Spot interruption, rebalance recommendations and instance state changes flow
through an SQS queue fed by EventBridge rules. The Terraform `karpenter` submodule
creates these resources.

### Consequences

- Positive: No node group per instance family. Bin-packing and consolidation
  reduce idle capacity. Spot interruptions drain gracefully ahead of time.
- Positive: Capacity policy is declarative and lives in git through Argo CD.
- Negative: Karpenter is another controller whose failure stops scale-up. It runs on
  the system node group with two replicas in prod, and it has a runbook
  ([karpenter-not-provisioning](../runbooks/karpenter-not-provisioning.md)).
- Negative: Karpenter's API changes between minor versions. The chart version is
  pinned, and CRDs ship as a separate chart so they upgrade explicitly.
- Negative: Nodes are not in a managed node group, so node-level changes go through
  NodePool and EC2NodeClass, not through the EKS console.

## Pros and Cons of the Options

### Cluster Autoscaler with managed node groups

- Good: Widely understood, mature, and works with any node group.
- Good: Node groups provide a stable target for upgrades.
- Bad: Scale-up waits on Auto Scaling group behaviour, and instance flexibility
  requires many groups.
- Bad: Spot diversification and consolidation are coarse.

### Karpenter

- Good: Launches the right instance type for pending pods directly, usually in tens
  of seconds.
- Good: Consolidation actively repacks pods and removes underused nodes.
- Good: Spot interruption handling is built in.
- Bad: New API surface to learn and operate.

### Fargate for everything

- Good: No node management.
- Bad: No DaemonSets, higher per-vCPU cost at steady state, and limited control over
  instance types. Not suitable as the default for all workloads.
