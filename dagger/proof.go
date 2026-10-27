package main

import "dagger/worlds/internal/dagger"

// Proof captures and judges the two synthetic delivery worlds through the real
// restic store. Export the evidence, verdicts and local repository to inspect it.
// No agent credentials or shared repository are used.
func (m *Worlds) Proof(
	// +defaultPath="/"
	// +ignore=["node_modules", ".git", "dagger", "runs"]
	harness *dagger.Directory,
) *dagger.Directory {
	return withPkl(dag.Container().From("node:22-bookworm")).
		WithExec([]string{"sh", "-c", "apt-get update -qq && apt-get install -y -qq restic jq"}).
		WithDirectory("/harness", harness).
		WithWorkdir("/harness").
		WithExec([]string{"bash", "examples/proof.sh", "/proof"}).
		Directory("/proof")
}
