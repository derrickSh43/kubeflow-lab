#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
load_versions
cluster_exists || die "no cluster. run: make up TIER=$TIER"
rc=0

step "Lab 02 - argo underneath"

if kc api-resources --api-group=argoproj.io 2>/dev/null | grep -qi workflow; then
  ok "argoproj.io Workflow CRD is registered"
else
  fail "no Workflow CRD - pipelines did not install"; rc=1
fi

if kc -n kubeflow get deploy workflow-controller >/dev/null 2>&1; then
  reps=$(kc -n kubeflow get deploy workflow-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [[ "${reps:-0}" -ge 1 ]]; then
    ok "workflow-controller is running (scale it back up if you finished question 4)"
  else
    warn "workflow-controller has 0 ready replicas - still on question 4?"
  fi
else
  fail "no workflow-controller deployment"; rc=1
fi

succeeded=$(kc -n kubeflow get workflows \
  -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null \
  | grep -c Succeeded || true)
if [[ "${succeeded:-0}" -ge 1 ]]; then
  ok "$succeeded workflow(s) have Succeeded"
else
  fail "no succeeded workflows yet - run: python3 pipeline.py --submit"; rc=1
fi

step "Your answers"
A="$(dirname "${BASH_SOURCE[0]}")/ANSWERS.md"
if [[ -f "$A" ]] && (( $(grep -cE '^\s*[0-9]+\.' "$A" || echo 0) >= 4 )); then
  ok "ANSWERS.md looks filled in"
else
  fail "ANSWERS.md missing or has fewer than 4 numbered answers"; rc=1
fi

echo
(( rc == 0 )) && ok "lab 02 complete" || fail "lab 02 not complete yet"
exit $rc
