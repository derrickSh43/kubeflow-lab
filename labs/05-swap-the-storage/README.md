# Lab 05 - Swap MinIO for real object storage

**Tier:** 0+
**Status:** stub

KFP writes artifacts to MinIO over the S3 API. Point it at LocalStack (or a
real bucket) instead and prove pipelines still run.

The lesson is how thin the abstraction is: a Secret, an endpoint, and a
bucket name. The follow-up question is the one that matters - what did you
just make your platform depend on, and what is your blast radius when that
dependency has an outage?
