# Tier 2

Tier 2 is tier 1 with the filter switched off - the full upstream `example`
overlay, serving stack included (KServe 0.18.0 on Knative 1.22.0).

Budget ~20GB of Docker memory and ~75GB of disk. Knative's activator and
autoscaler are chatty; if the cluster feels wedged, check them first.

The serving lab (lab 07) lives here.
