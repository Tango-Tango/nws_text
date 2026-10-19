#!/usr/bin/env bash
# .mashbill/toolchain.sh: install the toolchains of nws_text.
# Documentation: docs/repo-setup.md in the mashbill repo.
#
# mashbill runs this script once in each Environment build, as root, in /workspace,
# before .mashbill/setup.sh. The base image is Ubuntu 24.04 without Erlang or Elixir.
# Every later command runs in a login shell, which reads /etc/profile.d/*.sh.

# Step 1: stop at the first error, at an unset variable and at a failed command in a pipe.
set -euo pipefail

# The versions follow the newest entry of the CI matrix (.github/workflows/ci.yml): Elixir 1.19 / OTP 28.
# The builds come from builds.hex.pm, the same source as erlef/setup-beam in CI. They are precompiled.
OTP_VERSION=28.5.0.8
OTP_SHA256=9d1e254f31554bf26595a6a03164f8e38f48c74d5f60c00b589d581b8ad67781
ELIXIR_VERSION=1.19.6
ELIXIR_SHA256=d69db87541e1e5f4fa3f803353c01a30d4ef0e236c6bf53128b2bbed8b0b9b7e
ERLANG_HOME=/opt/erlang
ELIXIR_HOME=/opt/elixir

# Step 2: system packages from Ubuntu. The OTP build links against OpenSSL 3 and ncurses.
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libssl3t64 libncurses6 ca-certificates
rm -rf /var/lib/apt/lists/*

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Step 3: Erlang/OTP, outside the default PATH.
curl -fsSL -o "$tmp/otp.tar.gz" "https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/OTP-${OTP_VERSION}.tar.gz"
echo "${OTP_SHA256}  $tmp/otp.tar.gz" | sha256sum -c -
rm -rf "$ERLANG_HOME"
mkdir -p "$ERLANG_HOME"
tar -xzf "$tmp/otp.tar.gz" -C "$ERLANG_HOME" --strip-components=1
"$ERLANG_HOME/Install" -minimal "$ERLANG_HOME" >/dev/null

# Step 4: Elixir, built for OTP 28, outside the default PATH.
curl -fsSL -o "$tmp/elixir.zip" "https://builds.hex.pm/builds/elixir/v${ELIXIR_VERSION}-otp-28.zip"
echo "${ELIXIR_SHA256}  $tmp/elixir.zip" | sha256sum -c -
rm -rf "$ELIXIR_HOME"
mkdir -p "$ELIXIR_HOME"
unzip -q "$tmp/elixir.zip" -d "$ELIXIR_HOME"

# Write the exports to a profile file, so that setup.sh, the test command and the agent find erl, elixir and mix.
cat > /etc/profile.d/elixir.sh <<PROFILE
export PATH="$ELIXIR_HOME/bin:$ERLANG_HOME/bin:\$PATH"
PROFILE
# Read the exports now, so that the next steps of this script can use the new tools.
# shellcheck source=/dev/null
source /etc/profile.d/elixir.sh

# Step 5: Hex and rebar3 for mix deps.get. They go to ~/.mix and belong to the toolchain, not to the repo.
mix local.hex --force
mix local.rebar --force

# Step 6: a check at the end. A missing tool then fails the build here, with a clear message.
erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().'
elixir --version
