#!/bin/sh
set -eu

fail() {
  echo "error: $1"
  exit 1
}

TOKEN_FILE="${HOME}/.mapbox"
INFO_PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

if [ ! -f "$TOKEN_FILE" ]; then
  fail "Mapbox runtime token not found at ~/.mapbox. Add your public token before running the Mapbox map."
fi

token="$(tr -d '\n\r ' < "$TOKEN_FILE")"

if [ -z "$token" ]; then
  fail "~/.mapbox exists but is empty. Add your public Mapbox token before running the Mapbox map."
fi

case "$token" in
  pk.*) ;;
  *) fail "~/.mapbox must contain a public Mapbox runtime token that starts with pk." ;;
esac

if [ ! -f "$INFO_PLIST" ]; then
  fail "Generated Info.plist not found at $INFO_PLIST."
fi

/usr/libexec/PlistBuddy -c "Set :MBXAccessToken $token" "$INFO_PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :MBXAccessToken string $token" "$INFO_PLIST"

/usr/libexec/PlistBuddy -c "Set :FirebaseAppDelegateProxyEnabled false" "$INFO_PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Add :FirebaseAppDelegateProxyEnabled bool false" "$INFO_PLIST"

if [ -n "${SCRIPT_OUTPUT_FILE_1:-}" ]; then
  mkdir -p "$(dirname "$SCRIPT_OUTPUT_FILE_1")"
  touch "$SCRIPT_OUTPUT_FILE_1"
fi
