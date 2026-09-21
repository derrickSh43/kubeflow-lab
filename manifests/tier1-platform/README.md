# Tier 1 overlay

Tier 1 does **not** keep a hand-written list of Kubeflow components here, and
that is a deliberate choice.

Upstream ships a single all-in overlay at `example/kustomization.yaml`.
`scripts/up.sh` clones the pinned tag, copies that file, and comments out the
serving resources (`kserve`, `knative`, `models-web-app`) with a `#TIER1-OFF`
marker.

Why filter upstream instead of curating our own list? Because when you bump
`KUBEFLOW_VERSION` and upstream adds a component, a curated list silently
drops it and you debug a phantom for an hour. A filter picks it up for free,
and the marker makes the delta greppable:

```bash
grep -n '#TIER1-OFF' .state/overlay/kustomization.yaml
```

Drop your own patches in this directory and add them to the overlay in
`up.sh` if you want them applied every boot.
