# Labs

These are written for a **cloud engineer**, not a data scientist. Almost
nothing here is about models. It is about what Kubeflow is made of:
ingress, identity, tenancy, storage, controllers, and scheduling.

Each lab has a `README.md` with the task and a `verify.sh` that checks you
actually did it. The verify scripts check *state*, not that you ran a
command, so there is no way to fake them and no reason to.

| # | Lab | Tier | The infrastructure skill underneath |
|---|-----|------|--------------------------------------|
| 01 | trace-a-request | 0+ | ingress, Services, NodePort, Istio routing |
| 02 | argo-underneath | 0+ | CRDs, controllers, reconcile loops |
| 03 | multi-tenancy | 1+ | namespaces-as-tenants, RBAC, quotas |
| 04 | quota-squeeze | 0+ | ResourceQuota, requests/limits, Pending debugging |
| 05 | swap-the-storage | 0+ | S3 API, StorageClasses, stateful services |
| 06 | swap-the-idp | 1+ | OIDC, Dex, federated identity |
| 07 | serve-and-scale-to-zero | 2 | Knative autoscaling, revisions, cold start |
| 08 | upgrade-it | 1+ | version skew, breaking changes, rollback |

Labs 04-08 are stubs for now - 01 through 03 are written out in full.

## Running one

```bash
make up TIER=0          # once
cat labs/01-trace-a-request/README.md
bash labs/01-trace-a-request/verify.sh
```

## A note on the "break it" labs

Labs 04 and 08 ask you to break the cluster deliberately. That is the point.
You will spend far more of your real career reading `kubectl describe` output
than writing YAML, and a lab where nothing ever fails teaches you neither.
`make down && make up` is always there.
