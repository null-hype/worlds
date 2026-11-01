#!/usr/bin/env bash
# world.sh against a disposable restic repository and a world of no particular
# kind: the store keeps any directory. Needs restic and jq.
#
#   bash world/world.test.sh    # from the repo root
set -uo pipefail
cd "$(dirname "$0")/.."
export RESTIC_REPOSITORY="$(mktemp -d)" RESTIC_PASSWORD=test WORLD_CHECK=anything
world="bash world/world.sh"
fails=0
ok() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

src="$(mktemp -d)"; mkdir -p "$src/nested"; echo one > "$src/a.txt"; echo deep > "$src/nested/b.txt"
id1="$($world capture "$src" first run1)"
ok "a captured world has a full id" '[[ $id1 =~ ^[0-9a-f]{64}$ ]]'
ok "it is tagged with the check, its label and its run" \
  '[ "$(restic snapshots "$id1" --json | jq -c ".[0].tags | sort")" = "[\"check=anything\",\"label=first\",\"run=run1\"]" ]'
ok "an empty directory is not a world" '! $world capture "$(mktemp -d)" first 2> /dev/null'

read -r got at <<< "$($world restore first 2> /dev/null)"
ok "a label restores the world as the root of a fresh directory" '[ "$got" = "$id1" ] && [ "$(cat "$at/a.txt")" = one ] && [ "$(cat "$at/nested/b.txt")" = deep ]'
ok "the restore is apart from where it was made" '[ "$at" != "$src" ]'

echo two > "$src/a.txt"
id2="$($world capture "$src" first)"
read -r got at <<< "$($world restore first 2> /dev/null)"
ok "a label selects the newest world with it" '[ "$got" = "$id2" ] && [ "$(cat "$at/a.txt")" = two ]'
read -r got at <<< "$($world restore "$id1" 2> /dev/null)"
ok "an id restores exactly that world, whatever is newer" '[ "$got" = "$id1" ] && [ "$(cat "$at/a.txt")" = one ]'
$world restore nothing > /dev/null 2>&1; code=$?
ok "a label no world has exits 2" '[ "$code" = 2 ]'
WORLD_CHECK=another $world restore first > /dev/null 2>&1; code=$?
ok "worlds of another check are not selected" '[ "$code" = 2 ]'

# The world one delivery made: selected by it, whatever else shares its label.
idd1="$($world capture "$src" shared run2 d-1)"
echo three > "$src/a.txt"
idd2="$($world capture "$src" shared run2 d-2)"
echo four > "$src/a.txt"
idd3="$($world capture "$src" shared run2)"
ok "a world made by a delivery is tagged with it" \
  '[ "$(restic snapshots "$idd1" --json | jq -c ".[0].tags | sort")" = "[\"check=anything\",\"delivery=d-1\",\"label=shared\",\"run=run2\"]" ]'
read -r got at <<< "$($world restore shared 2> /dev/null)"
ok "the label selects the newest, which is not that delivery's" '[ "$got" = "$idd3" ]'
read -r got at <<< "$($world restore delivery=d-1 2> /dev/null)"
ok "delivery=<id> selects that delivery's world, though it is not the newest" '[ "$got" = "$idd1" ] && [ "$(cat "$at/a.txt")" = two ]'
read -r got at <<< "$($world restore delivery=d-2 2> /dev/null)"
ok "and another delivery's selects its own" '[ "$got" = "$idd2" ] && [ "$(cat "$at/a.txt")" = three ]'
$world restore delivery=d-3 > /dev/null 2>&1; code=$?
ok "a delivery that made no world exits 2" '[ "$code" = 2 ]'
WORLD_CHECK=another $world restore delivery=d-1 > /dev/null 2>&1; code=$?
ok "worlds of another check are not selected by delivery either" '[ "$code" = 2 ]'
$world capture "$src" shared run2 a,b > /dev/null 2>&1; code=$?
ok "a delivery id that cannot be a tag is refused" '[ "$code" = 2 ]'

echo; [ "$fails" = 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
