#!/usr/bin/env bash
# Fallback access path. Normally kind's extraPortMappings + the NodePort
# patch in up.sh already put the UI on localhost:8080, so you should not
# need this. Keep it for when you have broken the ingress on purpose.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions
cluster_exists || die "no cluster"

if [[ "$TIER" == "0" ]]; then
  NS=kubeflow; SVC=svc/ml-pipeline-ui; PORT=8080:80
else
  NS=istio-system; SVC=svc/istio-ingressgateway; PORT=8080:80
fi

info "forwarding $NS/$SVC -> http://localhost:8080   (ctrl-c to stop)"
TOOLBOX_PORTS="-p 8080:8080" tb_tty kubectl -n "$NS" port-forward \
  --address 0.0.0.0 "$SVC" "$PORT"
