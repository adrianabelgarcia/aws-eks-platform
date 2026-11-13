# Runbook: Node NotReady

| | |
|---|---|
| Severity | P2 (single node), P1 (more than 10% of nodes in a pool, or a zone) |
| Alert | `KubeNodeNotReady` (kube-prometheus-stack default rules) |
| Owner | Platform on-call |
| Related | [karpenter-not-provisioning](karpenter-not-provisioning.md), [pods-pending-imagepull-backoff](pods-pending-imagepull-backoff.md) |

## Symptoms

- `kubectl get nodes` shows `NotReady` or `SchedulingDisabled` for one or more nodes.
- Pods on the node stop receiving traffic, and pods scheduled to it stay `Terminating`.
- `KubeNodeNotReady` or `KubeNodeUnreachable` is firing.

## Triage

```bash
export CLUSTER=acme-prod   # or acme-staging
aws eks update-kubeconfig --name "$CLUSTER" --region us-east-1

# 1. Which nodes, which pool, which zone?
kubectl get nodes -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[-1].type,\
POOL:.metadata.labels.karpenter\\.sh/nodepool,SYSTEM:.metadata.labels.node-role,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone

# 2. Why? Read the conditions (MemoryPressure, DiskPressure, PIDPressure, Ready).
kubectl describe node <node> | sed -n '/Conditions:/,/Addresses:/p'
kubectl get events -A --field-selector involvedObject.kind=Node,involvedObject.name=<node> --sort-by=.lastTimestamp

# 3. Is the instance itself healthy? (Karpenter nodes map to a NodeClaim.)
kubectl get nodeclaim -o wide | grep <node>
INSTANCE_ID=$(kubectl get node <node> -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
aws ec2 describe-instance-status --instance-ids "$INSTANCE_ID" --include-all-instances
aws ec2 get-console-output --instance-id "$INSTANCE_ID" --output text | tail -50

# 4. Node-level diagnosis on Bottlerocket (no SSH; use a debug pod on the host).
kubectl debug node/<node> -it --profile=sysadmin --image=public.ecr.aws/amazonlinux/amazonlinux:2023 -- bash
#   inside: chroot /host, then journalctl -u kubelet / containerd, df -h /local (data volume)

# 5. Is the aws-node (VPC CNI) and kube-proxy pod healthy on that node?
kubectl -n kube-system get pods -o wide --field-selector spec.nodeName=<node>
```

## Mitigation

Prefer replacing the node over repairing it.

1. Cordon and drain so workloads move before the node disappears:
   ```bash
   kubectl cordon <node>
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --grace-period=60 --timeout=10m
   ```
2. Replace the instance:
   - Karpenter node: delete the NodeClaim. Karpenter launches a replacement and respects disruption budgets:
     `kubectl delete nodeclaim <name>`
   - System managed node group node: terminate the instance and let the Auto Scaling group replace it.
     `aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"`
     Do this one node at a time. The group's `max_unavailable_percentage` is 33.
3. If many nodes in one zone are NotReady, suspect the zone or the NAT path before the nodes:
   check the zone status on the AWS Health Dashboard and confirm the NAT gateway in that zone is `available`.
4. Confirm recovery: `kubectl get nodes` is `Ready`, and PodDisruptionBudgets are satisfied.

## Root cause (common)

- **DiskPressure**: the 80 GiB Bottlerocket data volume filled with images or container logs.
  Check `df` on the host. Images are pruned by kubelet GC thresholds, so repeated pressure usually means very large images.
- **Kubelet or containerd crash loop**: usually after a bad AMI or a manual change. Drift replacement handles this when the AMI is the cause.
- **VPC CNI (`aws-node`) failure**: IP exhaustion or an addon version mismatch. Prefix delegation needs free /28 blocks in the subnet.
- **Instance impairment**: hardware or hypervisor issue reported by EC2 status checks.
- **Security group or route change**: nodes lose the control plane endpoint or NAT egress. Compare with the last Terraform apply.

## Prevention

- Keep `expireAfter` and drift replacement on. Nodes that are patched by replacement cannot silently drift.
- Alert on `node_filesystem_avail_bytes` for the data volume below 15%.
- Keep the system node group at three nodes in prod, spread across three zones.
- After any EKS or AMI change, watch node readiness for 30 minutes before moving on (see [eks-version-upgrade](eks-version-upgrade.md)).
