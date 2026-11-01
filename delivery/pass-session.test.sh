#!/usr/bin/env bash
# Exercise the production login helper against Dagger's real cache. No Pass
# credentials, Jules calls, shared restic store, or two-hour wait are needed.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
tar -C "$root" --exclude=.git --exclude=node_modules --exclude=dagger/internal --exclude=runs -cf - . | tar -C "$scratch" -xf -
cp "$root/delivery/pass-session.proof.go" "$scratch/dagger/pass_session_proof.go"
dagger -m "$scratch" call pass-session-cache-proof

cp "$scratch/dagger/delivery.go" "$scratch/delivery.go.orig"

# Negative control: remove only the production cache key. A green result here
# would mean this test never exercised the bug it claims to prevent.
sed 's/return c.WithEnvVariable("PASS_LOGIN_DELIVERY", delivery).WithExec(args)/return c.WithExec(args)/' \
  "$scratch/dagger/delivery.go" > "$scratch/dagger/delivery.go.tmp"
mv "$scratch/dagger/delivery.go.tmp" "$scratch/dagger/delivery.go"
if dagger -m "$scratch" call pass-session-cache-proof > "$scratch/negative.out" 2> "$scratch/negative.err"; then
  echo 'FAIL: removing the delivery cache key did not reproduce the stale session' >&2
  exit 1
fi
if ! grep -q 'new delivery reused an expired login' "$scratch/negative.err"; then
  cat "$scratch/negative.err" >&2
  exit 1
fi
echo 'PASS: removing the delivery cache key reproduces the stale session' >&2

# Negative control: restore the production file, then remove only the logout. The
# fake client refuses to log in over an existing session, as the real one does.
# The cleanup of the session directory goes too: it would hide the missing logout.
cp "$scratch/delivery.go.orig" "$scratch/dagger/delivery.go"
grep -q 'pass-cli logout' "$scratch/dagger/delivery.go"
sed -e '/pass-cli logout/d' -e '/rm -rf "\/pass\//d' "$scratch/delivery.go.orig" > "$scratch/dagger/delivery.go"
if dagger -m "$scratch" call pass-session-cache-proof > "$scratch/negative2.out" 2> "$scratch/negative2.err"; then
  echo 'FAIL: removing the logout did not reproduce "Already authenticated"' >&2
  exit 1
fi
if ! grep -q 'Already authenticated' "$scratch/negative2.err"; then
  cat "$scratch/negative2.err" >&2
  exit 1
fi
echo 'PASS: removing the logout reproduces "Already authenticated"' >&2
