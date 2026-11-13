# ADR-0005: Kyverno CEL ValidatingPolicy instead of legacy ClusterPolicy

- Status: Accepted
- Date: 2026-11-13
- Deciders: Platform team

## Context and Problem Statement

Admission policies enforce the baseline: resource requests, pinned images, probes,
non-root and no privileged containers. The original design used Kyverno
`ClusterPolicy` resources. During validation, the Kyverno CLI and controller that
this repository targets (chart `kyverno` 3.10.0, application v1.20.0) rejected
`kyverno.io/v1` ClusterPolicy for create and update, with the message that legacy
policy types no longer execute and must be migrated to `policies.kyverno.io`.

Shipping the legacy form would have produced policies that look enforced in git and
do nothing in the cluster.

## Decision Drivers

- Policies must actually execute on the Kyverno version the cluster runs
- Testability in CI without a cluster
- Long-term direction of the Kyverno project
- Keeping the same guarantees: requests and limits, pinned images, probes, non-root,
  no privilege escalation or host namespaces

## Considered Options

1. Keep `ClusterPolicy` and pin Kyverno to a release that still executes it
2. Migrate to `ValidatingPolicy` (CEL) under `policies.kyverno.io/v1`
3. Replace Kyverno with OPA Gatekeeper or the Pod Security Admission controller alone

## Decision Outcome

Chosen option: **Migrate to `ValidatingPolicy` (CEL)**.

- Five policies live in `gitops/policies/`, one file per control.
- Each policy matches Pods directly and also Deployments, StatefulSets and DaemonSets, so
  violations are reported when the workload is applied, not only when a pod is created.
- A shared variable selects the pod template (`spec.template.spec`) or the pod spec, so one
  expression covers both kinds.
- Namespaces that run platform components are excluded by a `namespaceSelector`.
  Pod Security Admission, set on the `sample-api` namespace, remains the first line of defence.
- CI renders the sample workload and runs `kyverno apply` against the policies. The CLI
  exits non-zero on violations. A deliberately non-compliant Deployment fails all five policies,
  which confirms the checks are live and not vacuously passing.

Pod Security Admission (restricted) is enforced on the workload namespace as an independent
layer. Kyverno covers the rules PSA does not express, such as requests, limits, probe handlers
and image tags.

### Consequences

- Positive: Policies execute on the running Kyverno version, and CI tests them against the same CLI.
- Positive: CEL is evaluated in the API server path with bounded cost, and the policies
  do not need Kyverno's JMESPath engine.
- Negative: The resource kind changed from `ClusterPolicy` to `ValidatingPolicy`. Older
  documentation and examples will not match. This ADR is the reference.
- Negative: Some Kyverno features used by mutation or generation policies have their own
  CEL equivalents, which are not yet needed here.

## Pros and Cons of the Options

### Pin an older Kyverno

- Good: No policy rewrite.
- Bad: Pins the platform to a version that will leave support, and defers the migration.

### ValidatingPolicy (CEL)

- Good: Supported path, executes on current Kyverno, testable with `kyverno apply`.
- Bad: Syntax differs from ClusterPolicy and must be learned.

### Replace Kyverno

- Good: One fewer admission controller.
- Bad: Gatekeeper uses Rego, which the team does not use elsewhere, and the decision would
  be a larger change than the problem requires.
