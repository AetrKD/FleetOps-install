#!/bin/sh
# Download and verify a FleetOps release before requesting administrator access.
set -eu
umask 077
repository='AetrKD/FleetOps-install'
version=latest
if [ "${1:-}" = '--version' ]; then
  [ "$#" -ge 2 ] || { echo 'Missing release version' >&2; exit 1; }
  version=$2
  shift 2
  case "$version" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo 'Use a release tag such as v0.1.3' >&2; exit 1;; esac
  case "$version" in *[!v0-9.]*|*..*|*.) echo 'Invalid release version' >&2; exit 1;; esac
fi
[ "$(uname -s)" = Linux ] || { echo 'This installer supports Linux only.' >&2; exit 1; }
[ -r /etc/os-release ] || { echo 'Cannot identify the Linux distribution.' >&2; exit 1; }
. /etc/os-release
case "${ID:-}" in ubuntu|debian|fedora) ;; *) echo 'Supported distributions: Ubuntu, Debian, Fedora.' >&2; exit 1;; esac
[ ! -e /run/ostree-booted ] || { echo 'Use Fedora Server or Workstation; immutable editions are not supported.' >&2; exit 1; }
case "$(uname -m)" in x86_64|amd64) architecture=x64;; aarch64|arm64) architecture=arm64;; *) echo 'Unsupported CPU architecture.' >&2; exit 1;; esac
for command in curl tar sha256sum openssl mktemp; do
  command -v "$command" >/dev/null 2>&1 || { echo "Required download tool is missing: $command" >&2; exit 1; }
done
if [ "$version" = latest ]; then
  base="https://github.com/$repository/releases/latest/download"
else
  base="https://github.com/$repository/releases/download/$version"
fi
asset="fleetops-linux-$architecture.run"
workspace=$(mktemp -d "${TMPDIR:-/tmp}/fleetops-download.XXXXXX")
trap 'rm -rf "$workspace"' 0
trap 'exit 130' INT
trap 'exit 143' HUP TERM
cat > "$workspace/publisher.pem" <<'KEY'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA8tvuQGlCgEEOcju1VbeGEotrmFqh3ZmwoRob5anI0mk=
-----END PUBLIC KEY-----
KEY
fetch() {
  curl -q --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 20 --max-time 900 --retry 2 --max-filesize 536870912 "$1" -o "$2"
}
echo "Downloading FleetOps for $ID / $architecture..."
fetch "$base/$asset.sha256" "$workspace/checksum" || { echo 'No usable release was found. Check the release page or your connection.' >&2; exit 1; }
fetch "$base/$asset.sig" "$workspace/installer.sig"
fetch "$base/$asset" "$workspace/installer.run"
expected=$(cat "$workspace/checksum")
case "$expected" in *[!0-9a-f]*|'') echo 'Invalid release checksum.' >&2; exit 1;; esac
[ "${#expected}" = 64 ] || { echo 'Invalid release checksum length.' >&2; exit 1; }
actual=$(sha256sum "$workspace/installer.run")
actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo 'Download checksum mismatch. Installation was not started.' >&2; exit 1; }
openssl pkeyutl -verify -pubin -inkey "$workspace/publisher.pem" -rawin \
  -in "$workspace/installer.run" -sigfile "$workspace/installer.sig" >/dev/null 2>&1 || {
    echo 'Publisher signature verification failed. Installation was not started.' >&2; exit 1;
  }
echo 'Download verified. Starting installation...'
sh "$workspace/installer.run" "$@"
