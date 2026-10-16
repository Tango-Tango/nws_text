# Releasing `nws_text`

> **Human maintainers only. Agents must never run `scripts/release`, publish to
> Hex, create or push release tags, or create/publish GitHub releases.**

Releases use a two-step workflow so that the package version, changelog, and
release notes are reviewed in a pull request before anything is published.

## Prerequisites

- `git` with permission to push this repository.
- The GitHub CLI, [`gh`](https://cli.github.com/), installed and authenticated
  (`gh auth login`) with permission to create pull requests and releases.
- A Hex-authenticated maintainer account before the publish step (or the
  appropriate `HEX_API_KEY` in a controlled environment).
- A clean local checkout. Actual release actions must start from `main` exactly
  matching `origin/main`.

## 1. Prepare a release PR

From an up-to-date, clean `main`, choose the SemVer bump interactively:

```bash
scripts/release prepare
```

Enter `patch`, `feature` (a minor version bump), or `major`. The command reads
`@version` from `mix.exs`, calculates the next version, moves all current
`[Unreleased]` content to `## [X.Y.Z] - YYYY-MM-DD`, and leaves a new empty
`[Unreleased]` section. It creates and pushes `release/vX.Y.Z`, commits the
changes as `chore: release X.Y.Z`, and opens a **draft** PR with `gh`.

The first release is `0.1.0`. `@version` starts at `0.0.0`, so prepare it with:

```bash
scripts/release prepare --bump feature
```

For repeatable checks or automation, provide the bump explicitly:

```bash
scripts/release prepare --bump feature --dry-run
```

`--dry-run` only reports the calculated version and planned actions; it does
not change files, create branches, contact GitHub, or publish anything. Review
the draft PR and merge it normally.

## 2. Publish the merged release

Check out a clean, up-to-date `main` after the release PR is merged, then first
run the local preflight:

```bash
scripts/release publish --dry-run
```

This does not create a tag, contact GitHub, or upload to Hex. It runs the same
preflight as the real publish: test and development dependency fetches,
formatting, warning-free test compilation, tests, Credo, documentation, and a
local Hex tarball build. Test dependencies always use `MIX_ENV=test`; Credo,
documentation, and Hex operations use `MIX_ENV=dev`.

When ready, publish interactively:

```bash
scripts/release publish
```

The command validates the matching dated changelog section and that `vX.Y.Z`
does not already exist. It runs the preflight, creates and pushes an annotated
tag, creates a **draft** GitHub release using that version's changelog section
as its notes, and then runs `mix hex.publish`. Only after Hex succeeds does it
publish the GitHub release. To pass Hex's confirmation noninteractively, use
`--yes`; it is passed only to `mix hex.publish`:

```bash
scripts/release publish --yes
```

## Failure states and recovery

The script stops on authentication, Git/GitHub, preflight, or Hex failures and
prints the failed action. It deliberately does not roll back remote state:

- If release preparation fails after the branch was pushed, fix the branch and
  draft PR (or delete both) manually.
- If tagging or GitHub draft creation fails, resolve the permissions/network
  problem and inspect the existing tag before retrying. Never silently replace
  an existing tag.
- If Hex publishing fails, the tag and draft GitHub release are intentionally
  retained. Resolve the Hex error, verify the package was not published, then
  retry the remaining publish work deliberately.
- If Hex succeeds but the final GitHub publish fails, the GitHub release is
  still a draft. Publish that existing draft manually after verifying its notes
  and tag.

Do not use a new release version merely to hide a failed state; inspect the
remote tag, GitHub release, and Hex package state first.
