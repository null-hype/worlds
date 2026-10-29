#!/usr/bin/env bash
# registered-delivery's judge: restores a world from the store (an exact
# snapshot id, or a label for the newest with it) and judges it with
# Reconcile.pkl. The store knows nothing of this.
#
#   bash delivery/judge.sh <snapshot id | label> [valid | pass]   # from the repo root
#
# What it requires of the verdict is the second argument: valid (the default),
# the world and the protocol held, so Jev's agreeing or not is a finding; or
# pass, a valid run on which Jev agreed. Exits 0 when the verdict has it, 1
# when not (the verdict says why), 2 when no world has the label.
set -euo pipefail
requires="${2:-valid}"
[[ $requires = valid || $requires = pass ]] || { echo "requires valid or pass, not $requires" >&2; exit 2; }
export WORLD_CHECK=registered-delivery
restored="$(bash world/world.sh restore "$1")" || exit $?
read -r id world <<< "$restored"
at="$(mktemp -d)"
node delivery/facts.mjs "$world/spec.txt" "$at/facts.json" \
  "plan=$world/plan.json,$world/plan-run" "work=$world/work.json,$world/work-run"
pkl eval -f json -p observed="file://$at/facts.json" -p registered="file://$world/registered.json" \
  delivery/Reconcile.pkl > "$at/pkl.json"
# The verdict names the world it judged, so it can be had again.
verdict="${VERDICT:-$at/verdict.json}"
jq --arg id "$id" '. + {world: $id}' "$at/pkl.json" > "$verdict"
jq -r '"Registered: " + .registration' "$verdict"
for layer in "installed the world" "protocol the protocol" "measured Jev"; do
  echo "${layer#* }:"
  jq -r --arg k "${layer%% *}" '.[$k] | to_entries[] | "  " + (if .value then "✓ " else "✗ " end) + .key' "$verdict"
done
jq -r '.movements | to_entries[] | "  \(.value * 100 | round / 100)  \(.key)"' "$verdict"
jq -r '"Verdict: " + .verdict' "$verdict"
jq -r '"Next: " + .next' "$verdict"
jq -e --arg k "$requires" '.[$k]' "$verdict" > /dev/null || { jq -r '.verdict + " [world " + .world + "]"' "$verdict" >&2; exit 1; }
