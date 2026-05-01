#!/bin/sh
# Run while reproducing: Watch app on iPhone → Install Loggy on Apple Watch
# Requires: brew install libimobiledevice, iPhone unlocked + USB to Mac
set -e
UDID="${1:-$(idevice_id -l | head -1)}"
OUT="${2:-$HOME/Desktop/loggy-install-$(date +%Y%m%d-%H%M%S).log}"
echo "Logging iPhone $UDID → $OUT"
echo "Now: open Watch app → My Watch → Install Loggy on Watch (you have 90 seconds)"
echo "---"
(
  timeout 90 idevicesyslog -u "$UDID" 2>&1 \
    | grep -iE --line-buffered \
      'Loggy|installd|MIInstaller|MobileInstallation|PackageKit|embedded|Watch|com\.loggy|provision|signature|Install.*fail|denied|integrity|Placeholder'
) | tee "$OUT"
echo "---"
echo "Wrote: $OUT"
wc -l "$OUT"
