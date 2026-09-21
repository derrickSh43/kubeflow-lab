# What this repo actually builds

```
   your browser
        |
        | localhost:8080
        v
  +---------------------------------------------------+
  |  Docker                                           |
  |                                                   |
  |   +-------------------+   +-------------------+   |
  |   | toolbox container |   |  kind node        |   |
  |   | kubectl kustomize |   |  (control-plane)  |   |
  |   | kind helm k9s kfp |-->|  :30080 -> :8080  |   |
  |   +-------------------+   +-------------------+   |
  |         | docker.sock         +-------------+     |
  |         +-------------------->|  worker x2  |     |
  |                               +-------------+     |
  +---------------------------------------------------+
```

## Design decisions worth knowing

**Everything runs in Docker.** Nobody installs `kubectl`, `kustomize`,
`kind` or `helm` on their laptop. The toolbox image pins all of them, and
`make freeze` writes the resolved versions to `VERSIONS.lock`. Tool drift
between people is the number one cause of "works on my machine" in a shared
lab, and it is entirely preventable.

**The toolbox gets the Docker socket**, so `kind` creates sibling
containers rather than nested ones. It also joins the `kind` network, so
`kubectl` reaches the API server directly instead of via a published port.

**Two kubeconfigs, on purpose.** `.state/kubeconfig` points at the
in-network address for the toolbox; `.state/kubeconfig.host` points at
`127.0.0.1` for Lens or k9s running on your desktop. One file cannot serve
both, and pretending otherwise is a classic source of confusion.

**`kind create cluster --wait 0s`.** kind's own readiness probe dials the
host's loopback, which the toolbox container cannot see. Rather than fight
that, we skip kind's wait and do it ourselves with `kubectl` over the kind
network.

**Three nodes at tier 1+.** A single-node cluster hides every scheduling
lesson worth learning. With workers you can watch placement, cordon a node
mid-pipeline, and see what Kubeflow does about it.

**The install retries, and that is not a bug.** Upstream's documented
procedure is a retry loop, because the manifests contain CRDs and objects
of those CRDs in the same apply. The first several attempts are *expected*
to fail. `up.sh` retries up to 25 times with a 20s gap.

**Tier 1 filters upstream rather than curating a list.** `up.sh` copies
upstream's all-in `example/kustomization.yaml` and comments out the serving
resources with a `#TIER1-OFF` marker. A hand-maintained resource list would
silently drop new components on a version bump; a filter picks them up.

## What is in each tier

| | Tier 0 | Tier 1 | Tier 2 |
|---|---|---|---|
| Pipelines | standalone | distribution | distribution |
| Argo Workflows | yes | yes | yes |
| MinIO + MySQL | yes | yes | yes |
| Istio service mesh | - | yes | yes |
| Dex + oauth2-proxy | - | yes | yes |
| Profiles / multi-tenancy | - | yes | yes |
| Notebooks, Katib | - | yes | yes |
| KServe + Knative | - | - | yes |
| cert-manager | - | yes | yes |
| Login required | no | yes | yes |
| Docker memory | ~6GB | ~14GB | ~20GB |
| Disk | ~25GB | ~55GB | ~75GB |

## Component versions at Kubeflow 26.03.1

Pipelines 2.16.1 · KServe 0.18.0 · Istio 1.30.1 · cert-manager 1.20.2 ·
Dex 2.45.1 · Knative 1.22.0 · oauth2-proxy 7.15.2 · Spark Operator 2.5.0 ·
Model Registry 0.3.9

The Community Distribution moved to CalVer (`YY.MM[.patch]`) with roughly
two base releases a year, cut before KubeCon, and best-effort community
support for about six months. That support window is short enough that
"upgrade" is a routine operation here, not an event - which is why lab 08
exists.
