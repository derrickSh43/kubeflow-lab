# The toolbox. One image, one set of versions, every teammate identical.
#
# Nothing in this lab asks you to install kubectl/kustomize/kind locally.
# If a command needs a CLI, it runs in here. `make freeze` pins the
# floating versions into VERSIONS.lock so a shared repo stays reproducible.
FROM debian:12-slim

ARG TARGETARCH=amd64
ARG KUBECTL_VERSION=v1.36.4
ARG KIND_VERSION=v0.33.0
ARG KUSTOMIZE_VERSION=latest
ARG HELM_VERSION=latest
ARG K9S_VERSION=latest
ARG KFP_SDK_VERSION=latest

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq gettext-base bash make \
      python3 python3-pip python3-venv \
      docker.io \
 && rm -rf /var/lib/apt/lists/*

# --- kubectl ---------------------------------------------------------------
RUN curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client=true

# --- kind ------------------------------------------------------------------
RUN curl -fsSLo /usr/local/bin/kind \
      "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${TARGETARCH}" \
 && chmod +x /usr/local/bin/kind \
 && kind version

# --- kustomize -------------------------------------------------------------
# Kubeflow's manifests are pure kustomize; this is the single most important
# tool in the box. Upstream's install script fetches latest, so do the same
# unless VERSIONS.lock pins it.
RUN set -eux; \
    if [ "${KUSTOMIZE_VERSION}" = "latest" ]; then \
      curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
        | bash -s -- /usr/local/bin; \
    else \
      curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" \
        | bash -s -- "${KUSTOMIZE_VERSION#v}" /usr/local/bin; \
    fi; \
    kustomize version

# --- helm ------------------------------------------------------------------
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
      | env DESIRED_VERSION="$( [ "${HELM_VERSION}" = latest ] || echo "${HELM_VERSION}" )" bash \
 && helm version --short

# --- k9s (cluster TUI - you will live in this) -----------------------------
RUN set -eux; \
    v="${K9S_VERSION}"; \
    if [ "$v" = "latest" ]; then \
      v="$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r .tag_name)"; \
    fi; \
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${v}/k9s_Linux_${TARGETARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin k9s; \
    k9s version --short || true

# --- Kubeflow Pipelines SDK ------------------------------------------------
# Also gives you local execution - run a pipeline with NO cluster at all,
# which is how you should iterate on component code before deploying.
#
# This goes in a venv rather than --break-system-packages on purpose.
# `kfp-server-api` only ships an sdist, and building it against Debian 12's
# patched system setuptools fails with:
#     AttributeError: install_layout
# A venv with an up-to-date setuptools builds it cleanly. Verified, not
# guessed - this exact install failed before the venv was added.
ENV VIRTUAL_ENV=/opt/kfp
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN set -eux; \
    python3 -m venv "$VIRTUAL_ENV"; \
    pip install --no-cache-dir --upgrade pip setuptools wheel; \
    if [ "${KFP_SDK_VERSION}" = "latest" ]; then \
      pip install --no-cache-dir kfp kfp-kubernetes; \
    else \
      pip install --no-cache-dir "kfp==${KFP_SDK_VERSION}" kfp-kubernetes; \
    fi; \
    python -c "import kfp; print('kfp', kfp.__version__)"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
