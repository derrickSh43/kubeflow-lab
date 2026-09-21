#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions

step "Deleting cluster '$CLUSTER_NAME'"
if cluster_exists; then
  tb kind delete cluster --name "$CLUSTER_NAME"
  ok "cluster deleted"
else
  info "no cluster to delete"
fi

rm -f "$STATE_DIR/kubeconfig" "$STATE_DIR/kubeconfig.host"

if [[ "${1:-}" == "--nuke" ]]; then
  step "Nuking cached state and images"
  rm -rf "$STATE_DIR"
  docker image rm -f "$TOOLBOX_IMAGE" >/dev/null 2>&1 || true
  docker image prune -f >/dev/null 2>&1 || true
  ok "nuked. next 'make up' is a cold start (slow)"
else
  info "image cache kept - next 'make up' is much faster. 'make nuke' to clear it."
fi
