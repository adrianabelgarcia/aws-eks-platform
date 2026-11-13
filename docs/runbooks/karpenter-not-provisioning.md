# Runbook: Karpenter not provisioning

| | |
|---|---|
| Severity | P1 when application pods are Pending for more than 5 minutes in prod |
| Alert | Pending pods with `FailedScheduling` events. Karpenter controller errors in logs. |
| Owner | Platform on-call |
| Related | [pods-pending-imagepull-backoff](pods-pending-imagepull-backoff.md), [node-not-ready](node-not-ready.md) |

## Symptoms

- Pods are `Pending` with `0/N nodes are available` or `no instance type satisfied`.
- No new `NodeClaim` objects appear when load increases.
- Karpenter logs contain `InsufficientInstanceCapacity`, `UnauthorizedOperation`, `no subnets found` or `AMI not found`.
- Karpenter-provisioned capacity stops growing while the `general` or `baseline` pool shows its limit reached.

## Triage

```bash
kubectl get nodepools,ec2nodeclasses
kubectl get nodeclaims -o wide

# Conditions tell you which dependency is broken (NodeClassReady, SubnetsReady, SecurityGroupsReady,
# InstanceProfileReady, AMIsReady, ValidationSucceeded).
kubectl describe ec2nodeclass bottlerocket | sed -n '/Status:/,$p'
kubectl describe nodepool general | sed -n '/Status:/,$p'
kubectl describe nodepool baseline | sed -n '/Status:/,$p'

# Controller logs, newest first.
kubectl -n kube-system logs deploy/karpenter --since=30m | grep -iE 'error|fail|insufficient|unauthorized' | tail -50

# What is the pending pod asking for?
kubectl get pod <pending-pod> -o jsonpath='{.spec.nodeSelector}{"\n"}{.spec.tolerations}{"\n"}{.spec.containers[*].resources}{"\n"}'
```

Check each dependency:

```bash
# Discovery tags: must return subnets and security groups for this cluster.
aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=acme-prod" --query 'Subnets[].[SubnetId,AvailabilityZone]' --output table
aws ec2 describe-security-groups --filters "Name=tag:karpenter.sh/discovery,Values=acme-prod" --query 'SecurityGroups[].GroupId'

# Node role must exist and match the EC2NodeClass role.
aws iam get-role --role-name acme-prod-karpenter-node --query 'Role.Arn'

# Interruption queue: a growing backlog means the controller is stuck or unauthorised.
aws sqs get-queue-attributes --queue-url "$(aws sqs get-queue-url --queue-name acme-prod-karpenter --query QueueUrl --output text)" \
  --attribute-names ApproximateNumberOfMessages
```

## Mitigation

| Cause | Fix |
|---|---|
| `NodePool` at its `limits` | Raise `spec.limits` in `gitops/platform/karpenter/overlays/<env>/nodepool-*-patch.yaml`, merge the PR, and let Argo sync. For an emergency, scale down non-critical workloads first. |
| `InsufficientInstanceCapacity` on Spot | Karpenter falls back to On-Demand in `general`. If the pod pins `capacity-type: spot`, remove the selector temporarily. Widen instance categories if the problem repeats. |
| Pod requests no instance type fits | Check `nodeSelector`, `tolerations` and `requests`. A request larger than every allowed size (for example 40 GiB memory when the largest allowed size is smaller) can never schedule. |
| Subnet or security group tags missing | Restore the `karpenter.sh/discovery` tag through Terraform (`modules/network`, `modules/eks-cluster`). Do not tag by hand. |
| Controller unhealthy (crash loop, OOM) | `kubectl -n kube-system describe pod -l app.kubernetes.io/name=karpenter`. Raise memory in `terraform/modules/karpenter` and apply. Restarting the deployment is acceptable as a stopgap. |
| Controller cannot assume its role | Verify the Pod Identity association: `aws eks list-pod-identity-associations --cluster-name acme-prod --namespace kube-system`. |
| Interruption queue backlog | Check the controller is running and the queue policy allows EventBridge to send messages. |

Karpenter cannot run on nodes it provisions. If the system node group is full or unhealthy,
the controller itself may be Pending. Check with `kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter -o wide`.

## Root cause (common)

- Limits set too low for the traffic peak. Limits are a safety valve, but they are a silent outage when reached.
- Spot capacity exhausted in every AZ for the requested instance categories.
- Discovery tags removed or changed (for example by a tag-cleanup script).
- Karpenter IAM role or Pod Identity association changed in Terraform without a matching apply.

## Prevention

- Alert on `karpenter_nodepools_usage` / `karpenter_nodepools_limit` above 80%.
- Alert on `karpenter_pods_state` with pending pods older than 5 minutes.
- Keep at least two instance categories in every NodePool.
- Review NodePool limits as part of capacity planning each quarter.
