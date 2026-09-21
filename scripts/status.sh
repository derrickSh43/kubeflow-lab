#!/usr/bin/env bash
# What is running, and more usefully, what is NOT.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions

cluster_exists || die "no cluster. run: make up TIER=$TIER"

step "Nodes"
kc get nodes -o wide

step "Kubeflow namespaces"
kc get ns -l 'kubernetes.io/metadata.name' -o name 2>/dev/null \
  | grep -E 'kubeflow|istio|auth|cert-manager|knative|oauth2' || info "none yet"

step "Pods that are NOT Running/Completed"
# This is the line you actually care about during an install.
out=$(kc get pods -A --no-headers 2>/dev/null \
      | awk '$4!="Running" && $4!="Completed" {print}')
if [[ -z "$out" ]]; then
  ok "everything is Running or Completed"
else
  echo "$out"
  echo
  info "CrashLoopBackOff  -> kubectl logs -n <ns> <pod> --previous"
  info "Pending           -> kubectl describe pod -n <ns> <pod>  (look at Events)"
  info "ImagePullBackOff  -> usually just slow; wait, then check disk space"
fi

step "Recent warnings"
kc get events -A --field-selector type=Warning \
  --sort-by=.lastTimestamp 2>/dev/null | tail -15 || info "none"
