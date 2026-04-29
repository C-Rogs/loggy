#!/usr/bin/env bash
# Stream unified syslog from a USB-connected iPhone and filter for Loggy.
# Requires: brew install libimobiledevice
#
# Note: Use the UDID from `idevice_id -l` (USB). This differs from
# `xcrun devicectl list devices` “Identifier” when using wireless/Core Device.

set -euo pipefail

IDEVICE_SYSLOG="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
if [[ ! -x "$IDEVICE_SYSLOG" ]]; then
  echo "Install libimobiledevice: brew install libimobiledevice" >&2
  exit 1
fi

UDID="${LOGGY_DEVICE_UDID:-}"
if [[ -z "$UDID" ]]; then
  UDID="$(idevice_id -l 2>/dev/null | head -1 || true)"
fi
if [[ -z "$UDID" ]]; then
  echo "No iPhone UDID from idevice_id -l. Unlock the phone, trust this Mac, reconnect USB." >&2
  exit 1
fi

echo "Using device $UDID (set LOGGY_DEVICE_UDID to override)" >&2
echo "Streaming lines matching Loggy / com.loggy / subsystem… Ctrl+C to stop." >&2

exec "$IDEVICE_SYSLOG" -u "$UDID" 2>&1 | grep --line-buffered -iE 'Loggy|com\.loggy\.app|com\.loggy|subsystem.*loggy|category.*startup|category.*database'
