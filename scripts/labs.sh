#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
step "Labs"
for d in "$ROOT"/labs/*/; do
  [[ -f "$d/README.md" ]] || continue
  name=$(basename "$d")
  tier=$(grep -m1 -oP '^\*\*Tier:\*\*\s*\K.*' "$d/README.md" 2>/dev/null || echo "?")
  title=$(grep -m1 '^# ' "$d/README.md" | sed 's/^# //')
  printf '  %s%-22s%s tier %-4s %s\n' "$C_BLD" "$name" "$C_OFF" "$tier" "$title"
done
echo
info "run a lab's checks with: bash labs/<name>/verify.sh"
