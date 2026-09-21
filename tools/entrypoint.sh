#!/usr/bin/env bash
set -euo pipefail

# kind writes a kubeconfig pointing at 127.0.0.1:<random>, which is correct
# for the host but wrong from inside a sibling container. When we are on the
# `kind` network, rewrite the server to the in-network address instead.
if [[ -f /state/kubeconfig ]] && [[ "${CLUSTER_NAME:-}" != "" ]]; then
  if getent hosts "${CLUSTER_NAME}-control-plane" >/dev/null 2>&1; then
    sed -i -E "s#server: https://127\.0\.0\.1:[0-9]+#server: https://${CLUSTER_NAME}-control-plane:6443#" \
      /state/kubeconfig 2>/dev/null || true
  fi
fi

exec "$@"
