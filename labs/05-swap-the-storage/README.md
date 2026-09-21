# Lab 05 - Swap the bundled object store for real S3

**Tier:** 0+
**Status:** stub

KFP writes artifacts over the S3 API to an object store it bundles. Point
it at LocalStack (or a real bucket) instead and prove pipelines still run.

**Check which store you actually have before you start.** Pipelines 2.17
(tier 0) ships **SeaweedFS**; older builds and the version bundled in the
distribution may still ship **MinIO**. Both speak S3, the secret names
differ:

```bash
kubectl -n kubeflow get deploy | grep -Ei 'seaweed|minio'
kubectl -n kubeflow get secret | grep -Ei 'seaweed|minio|artifact'
```

Noticing this yourself is half the lab. A platform's "S3 bucket" is a
configurable implementation detail, and it changed under you between two
minor releases.

The lesson is how thin the abstraction is: a Secret, an endpoint, and a
bucket name. The follow-up question is the one that matters - what did you
just make your platform depend on, and what is your blast radius when that
dependency has an outage?
