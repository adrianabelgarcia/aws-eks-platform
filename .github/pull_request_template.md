## Summary

<!-- What changes, and why. One or two sentences. -->

## Scope

- [ ] Terraform (`terraform/`)
- [ ] GitOps (`gitops/`)
- [ ] Documentation (`docs/`, `README.md`)
- [ ] CI (`.github/`)

## Risk and rollout

<!-- Which environment does this touch first? Does it change a cluster-scoped object,
     a NodePool, a policy, or a Kubernetes version? Is a maintenance window needed? -->

## Verification

- [ ] `make check` passes locally (fmt, validate, tflint, checkov, GitOps validation)
- [ ] Terraform plan reviewed in the PR (CI comment). No unexpected destroys or replacements.
- [ ] Kyverno policies still pass against the sample workload (`make gitops`)
- [ ] Rollback path is clear (revert commit, or previous Argo CD revision)

## Checklist

- [ ] No secrets, account credentials or personal data in the diff
- [ ] New or changed Checkov skips have an inline justification
- [ ] Docs and runbooks updated if behaviour changed
