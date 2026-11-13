#!/usr/bin/env bash
# Validates the GitOps tree the same way CI does: YAML lint, kustomize render,
# schema validation (kubeconform with the CRDs catalog), and Kyverno policy
# evaluation of the rendered sample workload. Needs no cloud credentials.
#
# Usage: scripts/validate-gitops.sh [--schema-fallback]
#   --schema-fallback  also skip resources with no schema (last resort only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/.rendered"
K8S_VERSION="${K8S_VERSION:-1.34.0}"
CRDS_CATALOG='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

IGNORE_MISSING=()
if [[ "${1:-}" == "--schema-fallback" ]]; then
  IGNORE_MISSING=(-ignore-missing-schemas)
fi

# Kustomize overlays and bases that must render. Every directory that is a
# kustomization target is listed here so none can silently break.
KUSTOMIZE_TARGETS=(
  gitops/apps/sample-api/overlays/staging
  gitops/apps/sample-api/overlays/prod
  gitops/platform/karpenter/overlays/staging
  gitops/platform/karpenter/overlays/prod
)

# Plain-manifest directories (no kustomization file) validated as-is.
PLAIN_DIRS=(
  gitops/clusters/staging
  gitops/clusters/prod
  gitops/bootstrap
  gitops/policies
  gitops/platform/monitoring
  gitops/platform/storage
)

section() { printf '\n==> %s\n' "$1"; }

cd "$ROOT"
rm -rf "$OUT" && mkdir -p "$OUT"

section "yamllint"
yamllint -c .yamllint.yaml gitops

section "kustomize build"
for target in "${KUSTOMIZE_TARGETS[@]}"; do
  name="$(echo "$target" | tr '/' '_')"
  kustomize build "$target" > "${OUT}/${name}.yaml"
  echo "rendered $target -> $(grep -c '^kind:' "${OUT}/${name}.yaml") objects"
done

section "kubeconform (strict, CRDs catalog)"
FILES=("${OUT}"/*.yaml)
for dir in "${PLAIN_DIRS[@]}"; do
  FILES+=("$dir"/*.yaml)
done
kubeconform \
  -strict \
  -summary \
  -kubernetes-version "$K8S_VERSION" \
  -schema-location default \
  -schema-location "$CRDS_CATALOG" \
  ${IGNORE_MISSING[@]+"${IGNORE_MISSING[@]}"} \
  "${FILES[@]}"

section "kyverno apply (policies against rendered sample-api)"
# kyverno apply exits non-zero when any rule fails, so set -e is enough.
for env in staging prod; do
  echo "--- ${env}"
  kyverno apply gitops/policies \
    --resource "${OUT}/gitops_apps_sample-api_overlays_${env}.yaml"
done

section "all GitOps checks passed"
