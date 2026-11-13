# Runbook: Pods Pending or ImagePullBackOff

| | |
|---|---|
| Severity | P2 (non-customer-facing), P1 if it affects the sample-api rollout in prod |
| Alert | `KubePodNotReady`, `KubeDeploymentReplicasMismatch` |
| Owner | Owning application team, with platform support |
| Related | [karpenter-not-provisioning](karpenter-not-provisioning.md), [sample-api-slo-burn](sample-api-slo-burn.md) |

## Symptoms

- Pods stay `Pending` for minutes, or report `Pending` with `FailedScheduling`.
- Pods show `ErrImagePull` then `ImagePullBackOff`.
- A rollout stalls with some new pods running and others never becoming ready.

## Triage

```bash
NS=sample-api
kubectl -n "$NS" get pods -o wide
kubectl -n "$NS" get events --sort-by=.lastTimestamp | tail -30

# Pending: read the scheduler's reason.
kubectl -n "$NS" describe pod <pod> | sed -n '/Events:/,$p'

# ImagePullBackOff: read the registry error exactly.
kubectl -n "$NS" describe pod <pod> | grep -E 'Failed|Back-off|pull' | tail -10

# Does the image exist and is the tag correct? Check the manifest the cluster would use.
kubectl -n "$NS" get deploy sample-api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Decode the common messages:

| Message | Meaning |
|---|---|
| `manifest unknown` / `not found` | The tag or digest does not exist in the registry. |
| `unauthorized` / `403` | Missing or expired pull credentials for that registry. |
| `i/o timeout` / `dial tcp` | Node cannot reach the registry. Check NAT and the S3 gateway endpoint (for ECR layers). |
| `0/N nodes are available: N Insufficient cpu/memory` | Capacity or requests, not images. See Karpenter runbook. |
| `didn't match pod topology spread constraints` | Prod uses `DoNotSchedule` for zone spread. One zone is full or unavailable. |
| `didn't satisfy existing pods anti-affinity` / `untolerated taint` | Pod is pinned to a pool or taint it does not match. |

## Mitigation

1. **Bad or missing image tag**: fix the image in `gitops/apps/sample-api/overlays/<env>/`
   (the `images:` block) and merge. Do not `kubectl set image` on the live Deployment; Argo CD
   `selfHeal` reverts it.
2. **Registry credentials**: re-issue the pull credentials and update the Secret through the
   secret workflow. Do not paste credentials into the manifest.
3. **Resource shortage**: see [karpenter-not-provisioning](karpenter-not-provisioning.md). Scale
   the HPA ceiling only if the cluster has headroom.
4. **Zone spread blocking rollout (prod)**: the zone constraint is correct and should not be
   weakened to get a deploy through. Restore capacity in the zone, or revert the deploy with
   `argocd app rollback sample-api` (or `git revert` and merge).
5. **Stuck rollout**: the Deployment keeps old pods (`maxUnavailable: 0`), so traffic is not
   affected. Fix the cause, then the rollout resumes on its own.

## Root cause (common)

- A release commit referenced an image tag that CI did not push, often after a branch rename.
- Pull secrets rotated without updating the namespace.
- Requests larger than any node type Karpenter may launch.
- Topology constraints combined with a zone that lost capacity.

## Prevention

- Pin images by immutable tag or digest. Kyverno policy `disallow-latest-tag` enforces this.
- Keep requests realistic. Kyverno policy `require-resource-requests-limits` enforces that they exist.
- Run `make gitops` before opening a PR. It renders overlays and runs the policies.
- Alert on `kube_pod_status_phase{phase="Pending"}` lasting more than 10 minutes.
