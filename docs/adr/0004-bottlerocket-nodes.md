# ADR-0004: Bottlerocket for all cluster nodes

- Status: Accepted
- Date: 2026-11-13
- Deciders: Platform team

## Context and Problem Statement

Worker nodes run every workload, and their operating system sets the baseline for
patching, attack surface and node-level observability. The choices are Amazon Linux
2023, Ubuntu, Windows (not relevant here), and Bottlerocket, the container-optimised
OS from AWS.

## Decision Drivers

- Small attack surface: no package manager, no shell by default, read-only root filesystem
- Patch model: whole-OS updates that can be rolled out and rolled back
- Predictable node lifecycle with minimal per-node configuration drift
- Support for the EKS managed node AMI and Karpenter AMI selection
- Operational skills on the team

## Considered Options

1. Amazon Linux 2023 with custom bootstrap
2. Ubuntu EKS-optimised AMI
3. Bottlerocket

## Decision Outcome

Chosen option: **Bottlerocket**, for both the system managed node group (`BOTTLEROCKET_ARM_64`)
and Karpenter-provisioned nodes (`alias: bottlerocket@latest`).

Specifics:

- Immutable root volume, 4 GiB, and a separate 80 GiB data volume for images and writable state.
  Both are encrypted.
- Instance metadata requires IMDSv2 with hop limit 1. Pods cannot reach node credentials.
- Node updates happen by replacement, not in place. Karpenter's drift detection plus
  `expireAfter` (7 days in general, 14 days in baseline) roll new AMIs through the fleet.
  Disruption budgets cap how many nodes are replaced at once.
- Debugging uses the admin or control containers, reached through the Kubernetes API
  with `kubectl debug node`, not SSH. SSH access is not enabled in the node template.

Because `bottlerocket@latest` tracks new AMIs, prod is protected by the disruption budget
and the weekday business-hours block in the NodePool. Pinning to a specific Bottlerocket
release is a one-line change per NodePool, and it becomes the right choice once the
team has a release-validation pipeline (see README, "What I'd do next").

### Consequences

- Positive: Smaller CVE surface and fewer packages to patch.
- Positive: Node replacement is the only update path, so every node matches the AMI in git.
- Negative: No SSH. Troubleshooting depends on `kubectl debug node/...` and on the
  control container. Runbooks document this.
- Negative: Some third-party DaemonSets assume a full Linux userland. Each DaemonSet
  must be checked before it is added. The current platform charts run without issue.
- Negative: Custom kernel modules and host packages are not an option. Workloads that
  need them run on a dedicated node pool with a different AMI, which is not planned.

## Pros and Cons of the Options

### Amazon Linux 2023

- Good: Familiar, flexible, supports custom tooling on the host.
- Bad: Larger attack surface and package-level patching per node.

### Ubuntu

- Good: Familiar to many teams.
- Bad: Same package-level patching model, plus a larger image.

### Bottlerocket

- Good: Minimal, immutable, atomic updates, metadata hardening by default.
- Bad: Limited host access, which is the point, and some tooling must run as containers.
