#!/usr/bin/env bash
# Static checks only - no cluster, no Docker daemon load. Run this in CI.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

rc=0

step "shellcheck"
if docker run --rm -v "$ROOT:/mnt" -w /mnt koalaman/shellcheck:stable \
     -x -S warning scripts/*.sh tools/entrypoint.sh; then
  ok "shell scripts clean"
else
  fail "shellcheck found issues"; rc=1
fi

step "yaml"
if docker run --rm -v "$ROOT:/mnt" -w /mnt cytopia/yamllint \
     -c .yamllint.yml kind/ manifests/ labs/ .github/; then
  ok "yaml clean"
else
  fail "yamllint found issues"; rc=1
fi

step "kustomize dry-run (tier 0 only - needs network, no cluster)"
if tb kustomize build "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=${KFP_STANDALONE_VERSION:-2.17.0}" >/dev/null; then
  ok "tier 0 overlay builds"
else
  warn "could not build tier 0 overlay (network? toolbox not built?)"
fi

exit $rc
