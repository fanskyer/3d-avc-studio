#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FUNDING_FILE="$ROOT/../.github/FUNDING.yml"
[[ -s "$FUNDING_FILE" ]] || FUNDING_FILE="$ROOT/.github/FUNDING.yml"
BLOCKERS=0

blocker() {
  echo "- Blocker: $1"
  BLOCKERS=$((BLOCKERS + 1))
}

ok() {
  echo "- OK: $1"
}

echo "Open-source readiness audit:"

[[ -s "$ROOT/LICENSE" ]] && ok "MIT license file exists." || blocker "LICENSE is missing."
[[ -s "$FUNDING_FILE" ]] && ok "GitHub funding file exists." || blocker ".github/FUNDING.yml is missing."
[[ -s "$ROOT/Docs/OpenSourceRelease.md" ]] && ok "Open-source release docs exist." || blocker "Docs/OpenSourceRelease.md is missing."

if grep -qi 'MIT License' "$ROOT/LICENSE" &&
   grep -qi 'third-party software' "$ROOT/LICENSE" &&
   grep -qi 'patented codecs' "$ROOT/LICENSE" &&
   grep -qi 'external decoders' "$ROOT/LICENSE"; then
  ok "License includes decoder/patent boundary."
else
  blocker "LICENSE must state third-party decoder/patent boundary."
fi

if grep -qi 'Buy Me a Coffee' "$ROOT/README.md" &&
   grep -qi 'decoder binary' "$ROOT/README.md" &&
   grep -qi 'does not' "$ROOT/README.md"; then
  ok "README contains sponsorship and no-bundled-decoder positioning."
else
  blocker "README must describe sponsorship and no bundled decoder."
fi

if grep -q 'buy_me_a_coffee: 3davcstudio' "$FUNDING_FILE" ||
   grep -q 'https://www.buymeacoffee.com/3davcstudio' "$FUNDING_FILE"; then
  ok "Funding file includes Buy Me a Coffee link."
else
  blocker "Funding file must include Buy Me a Coffee link."
fi

if [[ -x "$ROOT/Scripts/package_open_source_release.sh" &&
      -x "$ROOT/Scripts/audit_open_source_release.sh" &&
      -x "$ROOT/Scripts/bootstrap_research_decoder.sh" ]]; then
  ok "Open-source package/audit scripts are executable."
else
  blocker "Open-source package/audit/bootstrap scripts must be executable."
fi

if grep -qi 'Apple Distribution' "$ROOT/README.md" ||
   grep -qi 'confirm-upload' "$ROOT/README.md" ||
   grep -qi 'installer-sign' "$ROOT/README.md"; then
  blocker "README should not expose internal release workflow."
else
  ok "README stays focused on the open-source preview."
fi

if [[ "$BLOCKERS" -gt 0 ]]; then
  echo
  echo "Open-source readiness audit failed with $BLOCKERS blocker(s)."
  exit 1
fi

echo "Open-source readiness audit passed."
