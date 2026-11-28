#!/bin/bash
# Submits a file to Apple's notary service, waits for the result and staples the ticket.
# Usage: Scripts/notarize.sh <file to submit (.zip or .dmg)> [<path to staple, defaults to the submitted file>]
#
# Credentials come from the environment, App Store Connect API key preferred:
#   APPLE_API_KEY (contents of the .p8, raw or base64), APPLE_API_KEY_ID, APPLE_API_ISSUER_ID
# or
#   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "usage: $0 <file to submit> [<path to staple>]" >&2
  exit 64
fi

submit="$1"
staple="${2:-$1}"

if [ -n "${APPLE_API_KEY:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ]; then
  key_dir="$(mktemp -d)"
  trap 'rm -rf "$key_dir"' EXIT
  key_file="$key_dir/AuthKey_$APPLE_API_KEY_ID.p8"
  if [[ "$APPLE_API_KEY" == -----BEGIN* ]]; then
    printf '%s\n' "$APPLE_API_KEY" > "$key_file"
  else
    printf '%s' "$APPLE_API_KEY" | base64 --decode > "$key_file"
  fi
  auth=(--key "$key_file" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  auth=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID")
else
  echo "error: no notarization credentials in the environment" >&2
  exit 78
fi

xcrun notarytool submit "$submit" "${auth[@]}" --wait --timeout 30m
xcrun stapler staple "$staple"
xcrun stapler validate "$staple"
