# kubeflow-lab

A local Kubeflow environment for **cloud engineers**, not data scientists.

The premise: Kubeflow is mostly a composition of infrastructure you already
care about — ingress, identity, tenancy, storage, controllers, scheduling —
with a thin ML layer on top. This repo boots that stack on a laptop, in
Docker, and then hands you labs that make you take it apart.

**One prerequisite: Docker.** No local `kubectl`, `kustomize`, `kind` or
`helm`. Everything runs in a pinned toolbox container, so you and everyone
you share this with get byte-identical tooling.

---

## Quickstart

**First time? Follow [`docs/SETUP.md`](docs/SETUP.md).** It is a complete
step-by-step from nothing, and it covers the Windows/WSL2 traps that fail
silently and cost people an afternoon.

If you already have a working Docker + WSL2 (or macOS/Linux) setup:

```bash
git clone <your-remote> kubeflow-lab
cd kubeflow-lab

make doctor           # will tell you if your machine can take it
make up TIER=0        # ~10 min on a warm cache
```

Then open <http://localhost:8080>.

```bash
make status           # what is running, and what is stuck
make sh               # toolbox shell: kubectl, kustomize, kind, helm, k9s, kfp
make labs             # list the labs
make pause            # stop for the day, keeping all cluster state
make resume           # back in under a minute
make down             # delete the cluster, keep the image cache
```

`make` runs in your host shell, not inside the toolbox. `make pause` is the
one to use between sessions — `make down` destroys pipeline runs, the
database and artifacts, which several labs build on. See
[Stopping for the day](docs/SETUP.md#stopping-for-the-day-and-coming-back).

## Tiers

Full Kubeflow wants 8 cores and 16GB of RAM. Starting there is a miserable
first experience, so pick your level:

| Tier | Docker RAM | Disk | What you get |
|------|-----------|------|--------------|
| **0** | ~6GB | ~25GB | Pipelines standalone. No mesh, no auth, no login. Boots fast. |
| **1** | ~14GB | ~55GB | Community Distribution minus serving: Istio, Dex, Profiles, Notebooks, Katib. **Most of the value is here.** |
| **2** | ~20GB | ~75GB | Everything, including KServe + Knative. |

```bash
make up TIER=1
```

`make doctor` refuses to start a tier your machine cannot actually hold,
which is kinder than finding out forty minutes in.

## What you will actually learn

| Kubeflow piece | The skill underneath |
|---|---|
| kind cluster config | node topology, labels, taints, scheduling |
| Istio ingress + VirtualServices | L7 routing, mTLS, sidecar injection |
| Dex + oauth2-proxy | OIDC flows, federated identity |
| Profiles controller | namespace-as-tenant, RBAC, ResourceQuota |
| Object store (SeaweedFS/MinIO) + PVCs | S3 API semantics, StorageClasses, CSI |
| Argo Workflows (under KFP) | CRDs, operators, reconcile loops |
| ml-pipeline MySQL + MLMD | stateful workloads, backup, migrations |
| KServe + Knative | scale-to-zero, revisions, canary |
| cert-manager | PKI, issuers, rotation |

## Labs

Eight labs, three written out in full. Each has a task and a `verify.sh`
that checks cluster **state** rather than that you ran a command.

| # | Lab | Tier |
|---|-----|------|
| 01 | Trace a request from browser to pod using only `kubectl` | 0+ |
| 02 | Find out what is actually running your pipeline (it is Argo) | 0+ |
| 03 | Prove the tenancy boundary — then try to break it | 1+ |
| 04 | Squeeze the quota until pipelines go `Pending` | 0+ |
| 05 | Swap the bundled object store for real S3 | 0+ |
| 06 | Replace Dex's static user with a real IdP | 1+ |
| 07 | Serve a model and let it scale to zero | 2 |
| 08 | Upgrade it and find out what breaks | 1+ |

Start with 01. Lab 03 is the highest-value one in the repo.

## Sharing this

The things that make a shared lab survive contact with other people:

- **Everything is pinned** in [`VERSIONS`](VERSIONS) — one file, one place.
  Run `make freeze` and commit `VERSIONS.lock` before you hand it over.
- **`make doctor`** catches the environment problems that would otherwise
  become your support tickets.
- **`make up` is idempotent.** Re-running after a failure is the normal
  recovery path, not a last resort.
- **The install retries on purpose.** Upstream's own procedure is a retry
  loop; the first several applies are expected to fail.

Next step if this gets real traffic: bake a kind node image with the
Kubeflow images pre-loaded and push it to a registry. Turns a 40-minute
cold pull into a 5-minute boot. It is the single biggest quality-of-life
win available.

## Layout

```
VERSIONS              every pin, one file
Makefile              the whole interface
kind/                 cluster topology
tools/                the pinned toolbox image
scripts/              doctor, up, pause, down, status, forward, lint
manifests/            tier overlays and patches
labs/                 the actual curriculum
docs/                 SETUP, wsl2-setup, architecture, troubleshooting
```

## Credentials

Tier 1+ ships upstream's static Dex user: `user@example.com` / `12341234`.
It is a lab default and it is public knowledge. Lab 06 replaces it. Do not
carry the habit anywhere near a network.

## Versions

Kubeflow Community Distribution **26.03.1** — Pipelines 2.16.1, KServe
0.18.0, Istio 1.30.1, cert-manager 1.20.2, Dex 2.45.1, Knative 1.22.0.
Tier 0 uses Pipelines standalone **2.17.0**. kind **v0.33.0** on Kubernetes
**1.36.4**.

The distribution uses CalVer with ~2 releases a year and ~6 months of
best-effort support, so upgrades are routine. See `VERSIONS` and lab 08.
