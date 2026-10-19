#!/usr/bin/env bash
# .mashbill/setup.sh: install the dependencies of nws_text.
# Documentation: docs/repo-setup.md in the mashbill repo.
#
# mashbill runs this script in each Environment build, at each Worktree start and after each move
# of the start commit, so it must be safe to run more than once. It must not change tracked files.
# The login shell reads /etc/profile.d/elixir.sh from .mashbill/toolchain.sh, so mix is on the PATH.

# Step 1: stop at the first error, at an unset variable and at a failed command in a pipe.
set -euo pipefail

# Step 2: the dependencies from mix.lock. --check-locked fails instead of changing the lock file.
mix deps.get --check-locked

# Step 3: compile the dev and test builds, so that the first test run of the agent is fast.
# deps/ and _build/ are in .gitignore.
mix compile
MIX_ENV="test" mix compile
