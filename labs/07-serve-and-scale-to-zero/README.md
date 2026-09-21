# Lab 07 - Serve a model and let it scale to zero

**Tier:** 2
**Status:** stub

Deploy a trivial InferenceService with KServe. Send traffic. Stop. Watch
Knative scale the pod to zero, then measure the cold start when traffic
returns.

Then decide, with numbers, whether scale-to-zero is a good idea for this
workload. That trade - cost versus tail latency - is the whole argument,
and it is one you will have with a product team eventually.
