#!/usr/bin/env bash
# Checks the cluster is in the state this lab needs, and that you wrote
# your answers down. It does not grade the answers - that is on you.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"
load_versions
cluster_exists || die "no cluster. run: make up TIER=$TIER"

rc=0

step "Lab 01 - trace a request"

if [[ "$TIER" == "0" ]]; then
  if kc -n kubeflow get svc ml-pipeline-ui -o jsonpath='{.spec.type}' 2>/dev/null | grep -q NodePort; then
    ok "ml-pipeline-ui is a NodePort service"
  else
    fail "ml-pipeline-ui is not NodePort - did 'make up' finish?"; rc=1
  fi
  eps=$(kc -n kubeflow get endpointslices -l kubernetes.io/service-name=ml-pipeline-ui \
          -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>/dev/null)
  [[ -n "$eps" ]] && ok "endpoints present: $eps" || { fail "no endpoints behind the service"; rc=1; }
else
  if kc -n istio-system get svc istio-ingressgateway >/dev/null 2>&1; then
    ok "istio-ingressgateway exists"
  else
    fail "no istio-ingressgateway"; rc=1
  fi
  if kc -n kubeflow get virtualservice centraldashboard >/dev/null 2>&1; then
    ok "centraldashboard VirtualService exists"
  else
    fail "no centraldashboard VirtualService"; rc=1
  fi
  n=$(kc -n kubeflow get pod -l app=centraldashboard \
        -o jsonpath='{.items[0].spec.containers[*].name}' 2>/dev/null | wc -w)
  if (( n >= 2 )); then
    ok "dashboard pod has $n containers (sidecar injected)"
  else
    warn "dashboard pod has $n container(s) - sidecar injection may be off. That is question 5."
  fi
fi

step "Your answers"
A="$(dirname "${BASH_SOURCE[0]}")/ANSWERS.md"
if [[ -f "$A" ]]; then
  lines=$(grep -cE '^\s*[0-9]+\.' "$A" || echo 0)
  if (( lines >= 4 )); then
    ok "ANSWERS.md has $lines numbered answers"
  else
    fail "ANSWERS.md has only $lines numbered answers, need at least 4"; rc=1
  fi
else
  fail "no ANSWERS.md in $(dirname "$A")"; rc=1
fi

echo
(( rc == 0 )) && ok "lab 01 complete" || fail "lab 01 not complete yet"
exit $rc
