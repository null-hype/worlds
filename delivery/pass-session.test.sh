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
