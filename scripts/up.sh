#!/usr/bin/env bash
# Boot the cluster and install Kubeflow at the requested tier.
# Idempotent: safe to re-run after a failure, which you WILL need.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions
validate_tier

printf '\n%skubeflow-lab up%s   tier %s - %s\n' "$C_BLD" "$C_OFF" "$TIER" "$(tier_name)"

# ---------------------------------------------------------------------------
if [[ "${SKIP_DOCTOR:-0}" != "1" ]]; then
  bash "$ROOT/scripts/doctor.sh" || die "doctor found blocking problems (SKIP_DOCTOR=1 to override)"
fi

bash "$ROOT/scripts/tools.sh" build

# --- 1. cluster ------------------------------------------------------------
step "Cluster"
CFG=$([[ "$TIER" == "0" ]] && echo "kind/cluster-tier0.yaml" || echo "kind/cluster.yaml")

if cluster_exists; then
  ok "cluster '$CLUSTER_NAME' already exists - reusing it"
else
  info "creating from $CFG with ${KIND_NODE_IMAGE%%@*}"
  # --wait 0s on purpose: kind's readiness probe dials 127.0.0.1 on the *host*,
  # which we cannot see from inside the toolbox. We do the waiting ourselves
  # below, over the kind network, where the address actually resolves.
  tb kind create cluster \
      --name "$CLUSTER_NAME" \
      --config "/work/$CFG" \
      --image "$KIND_NODE_IMAGE" \
      --kubeconfig /state/kubeconfig \
      --wait 0s
  ok "cluster created"
fi

# Two kubeconfigs, on purpose:
#   /state/kubeconfig       in-network, used by the toolbox
#   /state/kubeconfig.host  127.0.0.1, for Lens / k9s / kubectl on your desktop
tb kind export kubeconfig --name "$CLUSTER_NAME" --internal --kubeconfig /state/kubeconfig >/dev/null
tb kind export kubeconfig --name "$CLUSTER_NAME" --kubeconfig /state/kubeconfig.host >/dev/null
ok "kubeconfigs written to .state/"

step "Waiting for the control plane"
retry_until 30 10 kc wait --for=condition=Ready nodes --all --timeout=20s >/dev/null \
  || die "nodes never became Ready. 'make status' and docs/troubleshooting.md"
kc get nodes -o wide

# --- 2. install ------------------------------------------------------------
install_tier0() {
  step "Installing Kubeflow Pipelines standalone $KFP_STANDALONE_VERSION"
  info "no Istio, no Dex, no login screen - this tier is deliberately naked"

  local ref="$KFP_STANDALONE_VERSION"
  retry_until 5 15 kc apply -k \
    "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$ref" \
    || die "cluster-scoped resources failed"

  kc wait --for condition=established --timeout=120s crd/applications.app.k8s.io

  retry_until 10 20 kc apply -k \
    "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$ref" \
    || die "pipelines install failed after 10 attempts - see docs/troubleshooting.md"

  step "Exposing the UI on localhost:8080"
  kc -n kubeflow patch svc ml-pipeline-ui --type merge -p \
    '{"spec":{"type":"NodePort","ports":[{"port":80,"targetPort":3000,"nodePort":30080,"name":"http"}]}}'
  ok "patched ml-pipeline-ui to NodePort 30080 (mapped to host 8080 by kind)"
}

install_distribution() {
  local with_serving="$1"
  local up=/state/upstream

  step "Fetching Kubeflow Community Distribution $KUBEFLOW_VERSION"
  if tb test -d "$up/.git"; then
    ok "upstream already cloned"
  else
    tb rm -rf "$up"
    tb git clone --depth 1 --branch "$KUBEFLOW_VERSION" \
      https://github.com/kubeflow/manifests.git "$up" \
      || die "clone failed - is '$KUBEFLOW_VERSION' a real tag?"
    ok "cloned at tag $KUBEFLOW_VERSION"
  fi

  # Upstream ships one all-in overlay: example/. For tier 1 we take that file
  # and comment out the serving stack. Doing it by filtering upstream (rather
  # than hand-maintaining our own resource list) means a version bump does not
  # silently drop components we never knew existed.
  step "Building the overlay"
  tb rm -rf /state/overlay
  tb cp -r "$up/example" /state/overlay
  if [[ "$with_serving" == "no" ]]; then
    tb sed -i -E '/(kserve|knative|models-web-app)/ s@^(\s*-\s)@#TIER1-OFF \1@' \
      /state/overlay/kustomization.yaml
    local n; n=$(tb grep -c '^#TIER1-OFF' /state/overlay/kustomization.yaml || echo 0)
    ok "serving stack disabled ($n resource lines commented out)"
    info "diff it: git -C .state/upstream diff --no-index example/kustomization.yaml ../overlay/kustomization.yaml"
  else
    ok "full stack, serving included"
  fi

  step "Applying (this retries on purpose - CRDs race their consumers)"
  info "expect several failed attempts. 15-30 minutes is normal on a laptop."
  local n=1
  until tb bash -c 'kustomize build /state/overlay | kubectl apply --server-side --force-conflicts -f -'; do
    if (( n >= 25 )); then
      die "install did not converge after 25 attempts - see docs/troubleshooting.md"
    fi
    warn "attempt $n/25 incomplete, retrying in 20s ..."
    sleep 20; ((n++))
  done
  ok "manifests converged after $n attempt(s)"

  step "Exposing the dashboard on localhost:8080"
  kc -n istio-system patch svc istio-ingressgateway --type merge -p \
    '{"spec":{"type":"NodePort","ports":[
       {"name":"http2","port":80,"targetPort":8080,"nodePort":30080},
       {"name":"https","port":443,"targetPort":8443,"nodePort":30443}]}}' \
    || warn "could not patch istio-ingressgateway - use 'make forward' instead"
}

case "$TIER" in
  0) install_tier0 ;;
  1) install_distribution no ;;
  2) install_distribution yes ;;
esac

# --- 3. done ---------------------------------------------------------------
step "Done"
if [[ "$TIER" == "0" ]]; then
  cat <<TXT

  Pipelines UI   http://localhost:8080
  No login on this tier.

  Next:
    make status            what is running
    make sh                toolbox shell (kubectl, kfp, k9s)
    cat labs/README.md     start at lab 01

TXT
else
  cat <<TXT

  Central Dashboard   http://localhost:8080
  Login               user@example.com / 12341234   <-- CHANGE THIS, see docs/

  Pods are still settling. Give it 5-10 more minutes, then:
    make status            anything not Running is listed
    make sh                toolbox shell
    cat labs/README.md     start at lab 01

TXT
fi

info "host kubeconfig for Lens/k9s:  export KUBECONFIG=$STATE_DIR/kubeconfig.host"
