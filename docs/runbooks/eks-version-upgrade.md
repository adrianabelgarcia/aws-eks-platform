# Runbook: EKS version upgrade (blue/green node strategy)

| | |
|---|---|
| Severity | Planned change. Run in staging first, then prod in a maintenance window. |
| Owner | Platform team |
| Related | [node-not-ready](node-not-ready.md), [ADR-0004](../adr/0004-bottlerocket-nodes.md) |

EKS upgrades are one minor version at a time (for example 1.33 to 1.34). The control plane
upgrade is in place and managed by AWS. Node upgrades are separate and are done here as
blue/green, so there is always a known-good set of nodes to roll back to.

## Symptoms and triggers

- EKS announces end of standard support for the cluster's version.
- A platform component needs a newer Kubernetes version.
- Scheduled quarterly upgrade.

## Pre-flight (one day before)

1. **Deprecated API check.** Find manifests and clients using removed APIs:
   ```bash
   kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis
   # optional: run pluto against gitops/ and the cluster
   pluto detect-files -d gitops/ --target-versions k8s=v1.34.0
   ```
2. **Component matrix.** Confirm the target version is supported by each platform component:
   Karpenter (`karpenter_version` in `terraform/modules/karpenter`), AWS Load Balancer Controller
   (`targetRevision` in `gitops/clusters/<env>/aws-load-balancer-controller.yaml`), Argo CD,
   Kyverno, kube-prometheus-stack, and the EKS addons.
3. **Addon versions for the target version:**
   ```bash
   for a in vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver; do
     aws eks describe-addon-versions --addon-name "$a" --kubernetes-version 1.34 \
       --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion | [0]' --output text
   done
   ```
4. **Capacity.** Confirm the system node group and NodePool limits can absorb one replacement
   node per zone at once (see step 5).
5. **Freeze.** No other infrastructure or GitOps changes merge during the window.

## Procedure

### Staging

1. **Control plane.** In `terraform/envs/staging/terraform.tfvars`, change `kubernetes_version`
   to the target. Open a PR. The `terraform.yml` workflow plans it. Merge to apply.
   The control plane upgrade takes 20 to 40 minutes. Watch the cluster status in the EKS console or:
   ```bash
   aws eks describe-cluster --name acme-staging --query 'cluster.[version,status]' --output text
   ```
2. **Addons.** Addon versions are pinned to the cluster version's default (`most_recent = false`
   in `modules/eks-cluster`). After the control plane upgrade, verify each addon:
   ```bash
   aws eks list-addons --cluster-name acme-staging
   aws eks describe-addon --cluster-name acme-staging --addon-name vpc-cni --query 'addon.[addonVersion,status]'
   ```
   If an addon is `DEGRADED`, read `health.issues` in the same output before continuing.
3. **System nodes (blue/green).** The system node group runs on the old AMI until replaced. For the
   blue/green swap, add a second node group under a new key in `modules/eks-cluster/main.tf`
   (for example `system-v2` with the same settings and the target Kubernetes version). Apply it. Then:
   ```bash
   # Cordon the old group's nodes so new pods land on the new group.
   for n in $(kubectl get nodes -l node-role=system -o name); do kubectl cordon "$n"; done
   # Drain one at a time, letting PDBs (coredns, Argo CD, Kyverno, load balancer controller) keep quorum.
   kubectl get nodes -l node-role=system,eks.amazonaws.com/nodegroup=<old-group> -o name |
     while read -r n; do kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=15m; done
   ```
   Remove the old node group key in a follow-up PR after the drain is clean and the platform is healthy for 24 hours.
4. **Karpenter nodes (blue/green).** The `bottlerocket@latest` alias resolves to an AMI for the cluster's
   Kubernetes version, so once the control plane is upgraded, existing Karpenter nodes become drifted and are
   replaced at the pace the disruption budgets allow. That is rolling, not blue/green. For a clean cut that
   keeps the old fleet available for rollback, add a parallel EC2NodeClass and NodePool for the new generation
   (names with `-v2`), give the new pool a higher weight, and let consolidation drain the old pool. Delete the old pool after its NodeClaims are gone:
   ```bash
   kubectl get nodeclaims -l karpenter.sh/nodepool=general -o name | wc -l   # must reach 0 before deletion
   ```
5. **Validation.** Run the synthetic checks and the SLO dashboard for at least one business day. Confirm no
   `KubeNodeNotReady`, `KubePodNotReady` or SLO burn alerts fired.

### Prod

Repeat staging with these differences:

- Schedule outside the NodePool business-hours block (weekday 13:00 to 21:00 UTC), or do it in that window
  only with the disruption budget in mind.
- Upgrade the staging validation window first (at least 48 hours).
- The system node group has three nodes. Drain one node per zone at a time.
- Keep the old node group until the new one has held for 24 hours.

## Rollback

- Control plane: EKS does not support downgrading a cluster version. The rollback path is to keep the new
  control plane and roll back workloads and nodes. Keep this in mind before starting prod.
- Node groups: re-create the old node group key in Terraform and drain the new group back.
- Karpenter: move the weight back to the old NodePool. The old EC2NodeClass still exists until step 4 completes.

## Root cause (for the record)

Upgrades fail most often because of one of: a deprecated API still in a manifest, an addon or controller
that does not support the target version, a PDB that blocks drain, or a capacity shortage during drain.
The pre-flight steps exist to catch the first two before the window.

## Prevention

- Track EKS version end-of-support dates in the platform calendar. Upgrade at least twice a year.
- Keep platform component versions current through Dependabot and chart bumps, so each upgrade changes one thing.
- Keep the deprecated API check in CI once `pluto` is wired into the gitops workflow (listed in the README roadmap).
