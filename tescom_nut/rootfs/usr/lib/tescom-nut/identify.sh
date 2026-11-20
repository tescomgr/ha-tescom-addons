#!/usr/bin/env bash
# Tell which Tescom model a UPS on the shared 0001:0000 bridge is, from its
# running driver's reading, and put that model's settings in ups.conf.
#
#   identify.sh NAME OPTIONS_JSON CONF_DIR DATA_DIR
#
# Exit status:
#   0   nothing to change: the profile in ups.conf is the model's (or the
#       reading is none of ours)
#   10  ups.conf now has the model's settings: restart the driver
#   1   no reading yet: try again later
#
# The model is kept in DATA_DIR/models/NAME, so the next start uses it at
# once. UPSC (default upsc) can be replaced for tests.

set -euo pipefail

NAME="$1"
OPTIONS="${2:-/data/options.json}"
CONF="${3:-/etc/nut}"
DATA="${4:-/data}"
UPSC="${UPSC:-upsc}"

# shellcheck source=SCRIPTDIR/profiles.sh
. "$(dirname "$0")/profiles.sh"

log() { printf '[tescom-nut] %s\n' "$*" >&2; }

UPS_CONF="$CONF/ups.conf"
grep -qxF "[$NAME]" "$UPS_CONF" || exit 0

reading="$("$UPSC" "$NAME@localhost" 2>/dev/null)" || exit 1
grep -q '^battery.voltage.nominal: ' <<<"$reading" || exit 1
found="$(profile_from_reading <<<"$reading")"

# The profile ups.conf has now, from the marker genconf.sh writes.
current="$(awk -v n="[$NAME]" '
	/^\[.*\]$/ { in_it = ($0 == n); next }
	in_it && /^[[:space:]]*# Tescom profile: / { sub(/.*# Tescom profile: /, ""); print; exit }
' "$UPS_CONF")"

if [ -z "$found" ]; then
	log "UPS $NAME: not a Tescom model this add-on knows (battery $(sed -n 's/^battery.voltage.nominal: //p' <<<"$reading") V nominal); NUT's own settings are used"
	exit 0
fi
[ "$found" != "$current" ] || exit 0

extra="$(jq -r --arg n "$NAME" '.devices[] | select(.name == $n) | .config // [] | .[] | select(. != null and . != "")' "$OPTIONS" 2>/dev/null || true)"
block="$(echo "  # Tescom profile: $found"; settings_not_in "$extra" "$(profile_settings "$found")")"

# Put the block in place of the old one (from the marker to the section's end).
awk -v n="[$NAME]" -v block="$block" '
	function flush() { if (in_it && !done) { print block; done = 1 } }
	/^\[.*\]$/ { flush(); in_it = ($0 == n); skip = 0; print; next }
	in_it && /^[[:space:]]*$/ { flush(); skip = 0; print; next }
	in_it && /^[[:space:]]*# Tescom profile: / { skip = 1; next }
	in_it && skip { next }
	{ print }
	END { flush() }
' "$UPS_CONF" >"$UPS_CONF.tmp"
chmod --reference="$UPS_CONF" "$UPS_CONF.tmp" 2>/dev/null || true
mv -f "$UPS_CONF.tmp" "$UPS_CONF"

mkdir -p "$DATA/models"
echo "$found" >"$DATA/models/$NAME"
log "UPS $NAME: identified as $(profile_settings "$found" | sed -n 's/^desc = "\(.*\)"$/\1/p'); restarting its driver with that model's settings"
exit 10
