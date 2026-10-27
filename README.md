# Worlds

**Preserve the evidence behind an agent-produced change, then check the claim against that exact world.**

A passing check is hard to trust if its inputs have moved. Worlds captures a completed delivery's evidence as a restic snapshot, restores it independently of the producer, and evaluates the registered claim against the snapshot's exact ID. The verdict records that ID so you can inspect or judge the same evidence again.

```text
produce evidence → capture world → restore exact snapshot → judge claim → verdict + world ID
```

This is Richard Anthony's research prototype for verification infrastructure for agent-produced software. The smallest example below uses reconstructed delivery records, needs no API keys, and preserves both a disagreement and an agreement. It demonstrates evidence handling and judgement; it does **not** rerun a live agent or prove that its output is correct.

## Start here: one exact-world proof

With Docker running and [Dagger 0.21.8](https://docs.dagger.io/install) installed:

```sh
git clone https://github.com/null-hype/worlds.git
cd worlds
dagger call proof export --path runs/proof
```

The command runs [`examples/proof.sh`](examples/proof.sh) in a container with Node, Pkl, restic and jq. It:

1. Captures the existing **run 7** delivery records, including the predictions registered before the work and the before/after findings.
2. Replaces the producer's files with a passing delivery, captures it under the **same label**, then deletes the producer directory.
3. Restores and judges the **original snapshot ID**. Run 7 still disagrees with the prediction, even though the latest world passes.
4. Exports both restored worlds, verdicts, logs and the disposable restic repository.

Successful output ends with:

```text
PASS: run 7 still disagrees after a newer passing world replaced its label and the producer was deleted.
```

| Inspect | What it tells you |
| --- | --- |
| `runs/proof/run7.world/registered.json` | What was predicted, and when |
| `runs/proof/run7.world/{plan,work}.json` | The source-addressed before/after findings |
| `runs/proof/run7.verdict.json` | The validity checks, movements, verdict and exact `world` ID |
| `runs/proof/passing.verdict.json` | The comparison case, judged from a different snapshot |
| `runs/proof/restic/` | The captured evidence, independent of the deleted producer |

In run 7, the two file steps moved **+0.02** and **−0.09**; neither met the registered cooling rule. The judge reports a **valid disagreement**, distinct from an invalid run. The example succeeds only if it preserves that disagreement and the comparison case passes. It never changes the rule to make run 7 green.

[CI runs this same command and uploads the evidence as `exact-world-proof`.](https://github.com/null-hype/worlds/actions/workflows/proof.yml) Download an artifact to inspect the JSON and restored worlds without installing Dagger. The generated snapshot IDs vary between runs; each verdict identifies the snapshot it actually judged.

### Run directly or judge it again

With Bash, Node, Pkl, restic and jq on your PATH, the equivalent local command is:

```sh
bash examples/proof.sh runs/local-proof  # choose a new output directory each time
```

To judge the exported original snapshot again, from the repo root:

```sh
export RESTIC_REPOSITORY="$PWD/runs/proof/restic" RESTIC_PASSWORD=local-proof
bash delivery/judge.sh "$(cat runs/proof/run7.id)"
```

An expected valid disagreement exits **1**; inspect `Verdict:` rather than treating every nonzero exit as a broken instrument. A passing agreement exits **0**; a missing world exits **2**. These local demo repositories use a public demo password and contain only synthetic records.

## What is preserved—and what is not

A world is the evidence directory the producer writes and the judge reads. The store gives it an exact snapshot ID and `check=`, `label=` and optional `run=` tags. A label selects the newest matching world; an exact ID selects one immutable snapshot.

The first consumer is **registered-delivery**: plan a change, register predictions for that plan before approving work, run the delivery, capture its findings and judge whether the steps moved as predicted. Its judge keeps evidence validity, registration protocol and measured agreement separate.

The starter worlds are generated from [`delivery/worlds/Scenarios.pkl`](delivery/worlds/Scenarios.pkl), reconstructed from printed scores. Some approval/repair times are stand-ins that preserve ordering. They exercise the real store and judge, but are **not complete original run archives** and do not independently authenticate the registration. A restic snapshot preserves supplied evidence; it does not attest that the producer was truthful. It is not a VM snapshot or a replay of the whole execution environment.

The live agent experiment, credentials, repair loop and limitations are documented in [`delivery/README.md`](delivery/README.md). Start with the proof above; the live path requires private services and is outside the no-credentials example.

## Boundaries and source

- [`world/world.sh`](world/world.sh) and [`dagger/world.go`](dagger/world.go): capture and restore evidence. The store does not know the experiment's prediction rules.
- [`dagger/playwright.go`](dagger/playwright.go): collect Playwright evidence into a world.
- [`delivery/judge.sh`](delivery/judge.sh) and [`delivery/Reconcile.pkl`](delivery/Reconcile.pkl): restore and judge registered-delivery's evidence.
- [`witness`](https://github.com/null-hype/witness): present durable source-addressed findings and evidence in the editor. Worlds does not absorb the editor.
- [`features`](https://github.com/null-hype/features): install Witness and its Neovim client in Dev Containers.

Regression checks: `npm test` (requires restic, jq, Node and Pkl). No agent calls or private repository access are involved.

Extracted from [`agent-plugins`](https://github.com/null-hype/agent-plugins), the research monorepo, with filtered `jev-playwright/` history from `jev-delivery-nodes` ([PR #383](https://github.com/null-hype/agent-plugins/pull/383)); Dagger sources came from `.dagger/`. The scope here is preserved evidence and exact-world judgement, rather than a general agent platform.

## Work with Richard

I build and investigate systems where a green check needs an inspectable explanation. This work combines delivery automation, reproducibility, experimental design and developer tooling.

I'm available for senior software, security and AI infrastructure roles, and selected consulting work. [Professional overview](https://www.tidelands.dev/) · [GitHub](https://github.com/null-hype) · [Contact Richard](mailto:public.rant@pm.me)
