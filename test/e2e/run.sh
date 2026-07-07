#!/bin/sh
# End-to-end test for the background journal export.
#
# Downloads a real KOReader Linux release, installs this plugin pointed at a
# mock Hardcover GraphQL server, runs KOReader headless (SDL dummy video) in
# Docker, and exercises the silent export through a user patch which injects
# annotations and asserts on the result.
#
# Usage: test/e2e/run.sh
# Requires: docker, curl
set -e

KOREADER_VERSION="${KOREADER_VERSION:-v2026.03}"
ARCH=$(uname -m)
case "$ARCH" in
  arm64|aarch64) KO_ARCH="arm64" ;;
  *) KO_ARCH="x86_64" ;;
esac

E2E_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_DIR="$(cd "$E2E_DIR/../.." && pwd)"
WORK="$E2E_DIR/work"

mkdir -p "$WORK"

TARBALL="$WORK/koreader-$KOREADER_VERSION-$KO_ARCH.tar.xz"
if [ ! -f "$TARBALL" ]; then
  echo "Downloading KOReader $KOREADER_VERSION ($KO_ARCH)..."
  curl -sL -o "$TARBALL" \
    "https://github.com/koreader/koreader/releases/download/$KOREADER_VERSION/koreader-linux-$KO_ARCH-$KOREADER_VERSION.tar.xz"
fi

rm -rf "$WORK/lib" "$WORK/plugin" "$WORK/fixtures" "$WORK/out"
tar xf "$TARBALL" -C "$WORK" lib

# plugin copy pointed at the mock API, with a dummy token
mkdir -p "$WORK/plugin"
rsync -a --exclude=.git --exclude=spec --exclude=test "$PLUGIN_DIR/" "$WORK/plugin/hardcoverapp.koplugin/"
printf "return {\n  token = 'test-token'\n}\n" > "$WORK/plugin/hardcoverapp.koplugin/hardcover_config.lua"
sed -i.bak 's#local api_url = "https://api.hardcover.app/v1/graphql"#local api_url = "http://127.0.0.1:8181/v1/graphql"#' \
  "$WORK/plugin/hardcoverapp.koplugin/hardcover/lib/hardcover_api.lua"
rm -f "$WORK/plugin/hardcoverapp.koplugin/hardcover/lib/hardcover_api.lua.bak"

# koreader home with the book pre-linked and the test patch installed
mkdir -p "$WORK/fixtures/kohome/settings" "$WORK/fixtures/kohome/patches"
cp "$E2E_DIR/fixtures/hardcoversync_settings.lua" "$WORK/fixtures/kohome/settings/"
cp "$E2E_DIR/fixtures/2-journal-export-test.lua" "$WORK/fixtures/kohome/patches/"
cp "$E2E_DIR/fixtures/make_epub.py" "$E2E_DIR/fixtures/mock_api.py" "$E2E_DIR/fixtures/container_test.sh" "$WORK/fixtures/"

docker run --rm --platform "linux/$KO_ARCH" -v "$WORK:/work" python:3.12-slim-bookworm sh /work/fixtures/container_test.sh

EXIT_CODE=$(cat "$WORK/out/exit_code" 2>/dev/null || echo 99)
if [ "$EXIT_CODE" = "0" ]; then
  echo "E2E PASS"
else
  echo "E2E FAIL (exit code $EXIT_CODE), see $WORK/out/koreader.log"
  exit 1
fi
