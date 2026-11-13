# ADR-0003: Argo CD app-of-apps for cluster state

- Status: Accepted
- Date: 2026-11-13
- Deciders: Platform team

## Context and Problem Statement

The cluster runs many platform components (load balancer controller, ExternalDNS,
metrics server, Prometheus, Kyverno, Karpenter NodePools) and application workloads.
We need a way to deploy them that is reviewable, reproducible and drift-correcting,
and that does not require CI pipelines holding cluster credentials.

## Decision Drivers

- Pull-based delivery: the cluster reconciles itself from git
- Least privilege for CI, which should not need cluster write access
- Ordering: CRDs before custom resources, policies before workloads
- Drift detection and automatic repair
- A bootstrap that works on a freshly created cluster

## Considered Options

1. CI pipeline runs `helm upgrade` and `kubectl apply` against the cluster
2. Terraform manages every Kubernetes and Helm object
3. Argo CD with a single application for each component
4. Argo CD app-of-apps, with a root application that manages child applications
5. Argo CD ApplicationSets generating applications per cluster

## Decision Outcome

Chosen option: **Argo CD app-of-apps**, with one root `Application` per cluster.

Terraform installs Argo CD and creates the root application. The root application points at
`gitops/clusters/<env>`, which contains one `Application` manifest per component and an
`AppProject` that restricts sources and destinations. Sync waves set the order:

| Wave | Content |
|---|---|
| -10 | `AppProject platform` |
| 0 | Platform controllers and their CRDs (load balancer controller, ExternalDNS, metrics server, Kyverno, Prometheus stack, storage classes) |
| 5 | Kyverno policies, Karpenter NodePools and EC2NodeClass |
| 10 | SLO recording and alert rules |
| 20 | sample-api |

Each component's source is either a Helm chart at a pinned version or a path in this
repository. Environment-specific values live in the per-cluster `Application`, and the
Kustomize overlays carry the NodePool and workload differences.

Terraform does not manage Kubernetes objects other than Argo CD and Karpenter itself.
This keeps the Terraform state small and avoids two tools fighting over the same
objects.

The `ApplicationSet` option was rejected for now: with two clusters, explicit files are
easier to review than a generator. It is the natural next step when the number of
clusters grows.

### Consequences

- Positive: Git is the single source of truth for the cluster. Rollback is `git revert`.
- Positive: CI validates manifests (kustomize, kubeconform, Kyverno) without cluster access.
- Positive: `selfHeal` reverts manual `kubectl` edits, so drift does not persist.
- Negative: Argo CD is a critical controller. It runs on the system node group in HA
  mode in prod, and loss of Argo CD stops reconciliation but not running workloads.
- Negative: Application ordering depends on sync waves, which are easy to get wrong.
  The validation script renders everything, but it cannot simulate a live sync.
- Negative: Some charts create resources that Argo must track. Annotation-based resource
  tracking is enabled to avoid label collisions.

## Pros and Cons of the Options

### CI runs helm and kubectl

- Good: Simple to start.
- Bad: CI needs cluster write credentials, and drift is invisible until the next deploy.

### Terraform manages everything

- Good: One tool, one state.
- Bad: Slow plans for hundreds of objects, unreliable ordering for CRD-heavy charts, and
  no continuous reconciliation.

### App-of-apps

- Good: Explicit, reviewable, ordered, self-healing.
- Bad: More files, and sync-wave mistakes are only found at sync time.

### ApplicationSets

- Good: Generates per-cluster applications from one template.
- Bad: Generators add indirection that is hard to review for only two clusters.
