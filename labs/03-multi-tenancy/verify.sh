#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
load_versions
cluster_exists || die "no cluster. run: make up TIER=1"
[[ "$TIER" == "0" ]] && die "lab 03 needs tier 1+. run: make up TIER=1"
rc=0

step "Lab 03 - multi-tenancy"

if kc get crd profiles.kubeflow.org >/dev/null 2>&1; then
  ok "Profile CRD registered"
else
  fail "no Profile CRD - is this really tier 1?"; rc=1
fi

if kc get profile team-b >/dev/null 2>&1; then
  ok "profile 'team-b' exists"
else
  fail "no 'team-b' profile - run: kubectl apply -f profile-team-b.yaml"; rc=1
fi

if kc get ns team-b >/dev/null 2>&1; then
  ok "namespace 'team-b' created by the controller"

  # These are the objects the controller should have produced on its own.
  for kind in serviceaccount rolebinding resourcequota; do
    n=$(kc -n team-b get "$kind" --no-headers 2>/dev/null | wc -l)
    if (( n > 0 )); then
      ok "team-b has $n $kind(s)"
    else
      fail "team-b has no $kind - controller may still be reconciling"; rc=1
    fi
  done

  if kc -n team-b get authorizationpolicies --no-headers 2>/dev/null | grep -q .; then
    ok "team-b has an Istio AuthorizationPolicy (that is question 2)"
  else
    warn "no AuthorizationPolicy in team-b - worth understanding why"
  fi

  cpu=$(kc -n team-b get resourcequota -o jsonpath='{.items[0].spec.hard.cpu}' 2>/dev/null)
  [[ -n "$cpu" ]] && ok "quota applied: cpu=$cpu"
else
  fail "no 'team-b' namespace"; rc=1
fi

step "Your answers"
A="$(dirname "${BASH_SOURCE[0]}")/ANSWERS.md"
if [[ -f "$A" ]] && (( $(grep -cE '^\s*[0-9]+\.' "$A" || echo 0) >= 6 )); then
  ok "ANSWERS.md covers all six questions"
else
  fail "ANSWERS.md missing or has fewer than 6 numbered answers"; rc=1
fi

echo
(( rc == 0 )) && ok "lab 03 complete" || fail "lab 03 not complete yet"
exit $rc
