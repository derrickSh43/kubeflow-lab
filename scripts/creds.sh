#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_versions
cat <<TXT

  Tier 1+ ships Dex with a static password, straight from upstream:

      user@example.com / 12341234

  This is a LAB DEFAULT and it is public knowledge. It is also a good
  first exercise: lab 06 replaces Dex's static user with a real OIDC
  provider. Do not carry this habit into anything that faces a network.

  The hash lives in:  .state/upstream/common/dex/base/dex-config-map.yaml

TXT
[[ "$TIER" == "0" ]] && info "tier 0 has no auth at all - the UI is wide open by design"
