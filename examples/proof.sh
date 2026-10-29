#!/usr/bin/env bash
# Reuse the recorded-delivery fixtures and the real store/judge. No API calls.
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in restic jq node pkl; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 2; }
done
out="${1:-$(mktemp -d)/proof}"
mkdir -p "$(dirname "$out")"
mkdir "$out" || { echo "Choose a new output directory: $out" >&2; exit 2; }
out="$(cd "$out" && pwd)"
# Never use the caller's shared repository or credentials.
export RESTIC_REPOSITORY="$out/restic" RESTIC_PASSWORD=local-proof
export RESTIC_CACHE_DIR="$out/cache"
export WORLD_CHECK=registered-delivery
unset RESTIC_PASSWORD_FILE RESTIC_PASSWORD_COMMAND

echo "Synthetic replay: capture two completed deliveries, then judge exact snapshots."
cp -R delivery/worlds/run7 "$out/producer"
old="$(bash world/world.sh capture "$out/producer" proof run7)"
# Change the producer and advance the same label to a passing case.
rm -rf "$out/producer"
cp -R delivery/worlds/first-passing "$out/producer"
new="$(bash world/world.sh capture "$out/producer" proof first-passing)"
rm -rf "$out/producer"
printf '%s\n' "$old" > "$out/run7.id"
printf '%s\n' "$new" > "$out/passing.id"

# An expected disagreement is evidence: the run is valid, so the judge is green;
# requiring Jev's agreement as well, it is red. A failed instrument must still fail.
VERDICT="$out/run7.verdict.json" bash delivery/judge.sh "$old" > "$out/run7.log" 2>&1
cat "$out/run7.log"
status=0
bash delivery/judge.sh "$old" pass > /dev/null 2>&1 || status=$?
test "$status" -eq 1
jq -e --arg id "$old" '.world == $id and .valid and (.measuredPass | not) and (.pass | not)' "$out/run7.verdict.json" >/dev/null
VERDICT="$out/passing.verdict.json" bash delivery/judge.sh "$new" pass > "$out/passing.log" 2>&1
jq -e --arg id "$new" '.world == $id and .valid and .measuredPass and .pass' "$out/passing.verdict.json" >/dev/null
read -r latest restored <<< "$(bash world/world.sh restore proof)"
test "$latest" = "$new"
cp -R "$restored" "$out/passing.world"
read -r exact restored <<< "$(bash world/world.sh restore "$old")"
test "$exact" = "$old"
diff -r delivery/worlds/run7 "$restored"
cp -R "$restored" "$out/run7.world"
echo
echo "PASS: run 7 still disagrees after a newer passing world replaced its label and the producer was deleted."
echo "Inspect: $out/run7.world/ and $out/run7.verdict.json"
echo "Compare: $out/passing.world/ and $out/passing.verdict.json"
echo "Repository: $RESTIC_REPOSITORY (local demo password: local-proof)"
