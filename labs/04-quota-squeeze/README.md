# Lab 04 - Squeeze the quota until it breaks

**Tier:** 0+
**Status:** stub

Tighten `team-b`'s ResourceQuota below what a pipeline run needs. Submit
lab 02's pipeline into that namespace. Watch pods sit `Pending`.

Then debug it the way you would at 2am, from `kubectl describe pod` events
back to the quota object, and write down the chain. Bonus: do the same with
a `LimitRange` instead and note why the failure looks different.
