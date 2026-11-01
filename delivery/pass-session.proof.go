// Copied into a temporary module by pass-session.test.sh; this adds no public
// function to the production module. It calls the real production helpers.
package main

import (
	"context"
	"dagger/worlds/internal/dagger"
	"encoding/json"
	"fmt"
	"time"
)

// +cache="never"
func (m *Worlds) PassSessionCacheProof(ctx context.Context) (string, error) {
	clock := dag.CacheVolume("pass-session-proof-" + time.Now().UTC().Format(time.RFC3339Nano))
	c := dag.Container().From("node:22-bookworm").
		WithMountedCache("/clock", clock).
		WithNewFile("/usr/local/bin/pass-cli", `#!/bin/sh
set -eu
dir=$PROTON_PASS_SESSION_DIR
now=$(cat /clock/now)
if [ "$1" = logout ]; then
  rm -f "$dir/issued"
  exit 0
fi
if [ "$1" = login ]; then
  [ -n "${PROTON_PASS_PERSONAL_ACCESS_TOKEN:-}" ] || exit 2
  # Like the real client: a session in the directory, expired or not, blocks login.
  if [ -e "$dir/issued" ]; then
    echo 'Client is already authenticated. Log out if you want to log in again' >&2
    echo 'Error: Already authenticated' >&2
    exit 1
  fi
  mkdir -p "$dir"
  printf '%s\n' "$now" > "$dir/issued"
  exit 0
fi
issued=$(cat "$dir/issued")
[ "$((now - issued))" -lt 7200 ] || { echo 'No active session' >&2; exit 1; }
echo '{"shares":[]}'
`, dagger.ContainerWithNewFileOpts{Permissions: 0755}).
		WithExec([]string{"sh", "-ec", "echo 0 > /clock/now; : > /clock/plans"})
	// The plan logs in at time zero. It must execute only once, even when a
	// new delivery authenticates at a later time against this same plan.
	planned := withLogins(c, dag.SetSecret("fake-planner", "test-only"), dag.SetSecret("fake-judge", "test-only")).
		WithExec([]string{"bash", "-ec", ". /logins.sh; echo planned >> /clock/plans; echo stable-run > /plan-id"})
	first := withFreshPassLogins(planned, "delivery-a", "judge")
	if _, err := first.Sync(ctx); err != nil {
		return "", err
	}
	// A login with only a secret and no delivery key is also cached. Prime it
	// before advancing the shared clock; the clock is outside the image layer.
	secretOnly := planned.WithExec([]string{"bash", "-ec", `. /logins.sh "$@"`, "pass-login", "judge"})
	if _, err := secretOnly.Sync(ctx); err != nil {
		return "", err
	}
	advance := func(c *dagger.Container, now string) error {
		_, err := c.WithExec([]string{"sh", "-ec", "echo " + now + " > /clock/now"}).Sync(ctx)
		return err
	}
	read := func(c *dagger.Container, phase string) (bool, error) {
		code, err := c.WithEnvVariable("READ_PROOF", phase).
			WithExec([]string{"sh", "-ec", `PROTON_PASS_SESSION_DIR="$PASS_SESSION_JUDGE" pass-cli share list`}, dagger.ContainerWithExecOpts{Expect: dagger.ReturnTypeAny}).ExitCode(ctx)
		return code == 0, err
	}
	if err := advance(planned, "7201"); err != nil {
		return "", err
	}
	checks := map[string]bool{}
	for name, old := range map[string]*dagger.Container{
		"expired_plan_rejected":              planned,
		"secret_only_login_still_expired":    secretOnly,
		"same_delivery_reuses_expired_login": withFreshPassLogins(planned, "delivery-a", "judge"),
	} {
		ok, err := read(old, name)
		if err != nil {
			return "", err
		}
		checks[name] = !ok
	}
	second := withFreshPassLogins(planned, "delivery-b", "judge")
	ok, err := read(second, "new-delivery")
	if err != nil {
		return "", err
	}
	checks["new_delivery_refreshes_judge"] = ok
	if !ok {
		return "", fmt.Errorf("new delivery reused an expired login")
	}
	// Model another long phase before the final registered-plan read. The
	// final evidence container needs its own login even within one delivery.
	if err := advance(second, "14402"); err != nil {
		return "", err
	}
	produced := second.WithNewFile("/evidence", "complete")
	ok, err = read(withFreshPassLogins(produced, "delivery-b", "judge"), "final-read")
	if err != nil {
		return "", err
	}
	checks["final_read_refreshes_judge"] = ok
	count, err := planned.WithExec([]string{"sh", "-ec", "wc -l < /clock/plans"}).Stdout(ctx)
	if err != nil {
		return "", err
	}
	checks["plan_executed_once"] = count == "1\n"
	for name, ok := range checks {
		if !ok {
			return "", fmt.Errorf("cache regression: %s", name)
		}
	}
	b, err := json.MarshalIndent(checks, "", "  ")
	return string(b), err
}
