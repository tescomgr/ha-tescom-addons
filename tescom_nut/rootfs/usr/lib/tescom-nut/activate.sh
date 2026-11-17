#!/usr/bin/env bash
# Activate the Tescom Primes in ups.conf and fetch their driver.
#
#   activate.sh OPTIONS_JSON CONF_DIR DATA_DIR
#
# tescom_prime is not part of this add-on: Tescom Connect hands it out for a
# UPS registered on myTescom. For every ups.conf section whose driver is
# tescom_prime, the matching device in the options must give the UPS's serial
# number and its activation code (shown on the UPS's page in myTescom):
#
#   POST $CLOUD/addon/activate         {serial, code, install_id, arch, addon_version}
#     200 {token, expires_at, model?, driver: {version, nut, sha256}}
#     4xx {error}                       wrong code, unknown serial, ...
#   GET  $CLOUD/addon/drivers/tescom_prime?arch=ARCH   Authorization: Bearer TOKEN
#     200 the driver binary (its SHA-256 is the one activate gave)
#
# docs/CLOUD-API.md in the repository has the details. An activation is kept
# in DATA_DIR and used while Tescom Connect cannot be reached, until it
# expires. A UPS that is not activated is left out of ups.conf, with a log
# line saying what to do.
#
# Environment (for tests): TESCOM_CLOUD (default from the options' cloud_url,
# else https://connect.tescom.gr/v1), NUT_DRIVER_DIR (default /usr/lib/nut),
# ADDON_VERSION, ARCH (default from uname -m).

set -euo pipefail

OPTIONS="${1:-/data/options.json}"
CONF="${2:-/etc/nut}"
DATA="${3:-/data}"
CLOUD="${TESCOM_CLOUD:-$(jq -r '.cloud_url // empty' "$OPTIONS")}"
CLOUD="${CLOUD:-https://connect.tescom.gr/v1}"
CLOUD="${CLOUD%/}"
DRIVER_DIR="${NUT_DRIVER_DIR:-/usr/lib/nut}"
ADDON_VERSION="${ADDON_VERSION:-unknown}"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
	arm64) ARCH=aarch64 ;;
	amd64) ARCH=x86_64 ;;
esac
MYTESCOM="https://my.tescom.gr"

log() { printf '[tescom-nut] %s\n' "$*" >&2; }

UPS_CONF="$CONF/ups.conf"
mkdir -p "$DATA/activation" "$DATA/drivers/$ARCH"

# The ups.conf sections that use tescom_prime.
primes=()
while IFS= read -r name; do
	[ -n "$name" ] && primes+=("$name")
done < <(awk '
	/^\[.*\]$/ { name = substr($0, 2, length($0) - 2); next }
	name != "" && $1 == "driver" && $3 == "tescom_prime" { print name }
' "$UPS_CONF")
[ "${#primes[@]}" -gt 0 ] || exit 0

if [ ! -s "$DATA/install_id" ]; then
	cat /proc/sys/kernel/random/uuid >"$DATA/install_id" 2>/dev/null \
		|| od -An -N16 -tx1 /dev/urandom | tr -d ' \n' >"$DATA/install_id"
fi
install_id="$(tr -d '\n' <"$DATA/install_id")"
now="$(date +%s)"

drop() { # name reason
	log "UPS $1 is left out: $2"
	awk -v n="[$1]" '
		/^\[.*\]$/ { skip = ($0 == n) }
		!skip
	' "$UPS_CONF" >"$UPS_CONF.tmp" && mv -f "$UPS_CONF.tmp" "$UPS_CONF"
}

how="Register the UPS on myTescom ($MYTESCOM), then enter its serial number and the activation code from its page there in the add-on's configuration."

active=()   # names activated
token=""    # a token to download the driver with
sha=""      # the driver's SHA-256 that Tescom Connect gave

for name in "${primes[@]}"; do
	serial="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .serial // ""' "$OPTIONS" | head -1)"
	code="$(jq -r --arg n "$name" '.devices[] | select(.name == $n) | .activation_code // ""' "$OPTIONS" | head -1)"
	serial="$(printf '%s' "$serial" | tr 'a-z' 'A-Z' | tr -cd 'A-Z0-9')"
	code="$(printf '%s' "$code" | tr -cd '0-9')"
	if [ -z "$serial" ] || [ -z "$code" ]; then
		drop "$name" "the Tescom Prime needs activating. $how"
		continue
	fi
	cache="$DATA/activation/$serial.json"

	body="$(jq -nc --arg s "$serial" --arg c "$code" --arg i "$install_id" --arg a "$ARCH" --arg v "$ADDON_VERSION" \
		'{serial: $s, code: $c, install_id: $i, arch: $a, addon_version: $v}')"
	set +e
	reply="$(curl -sS -m 20 -X POST -H 'Content-Type: application/json' -d "$body" \
		-w '\n%{http_code}' "$CLOUD/addon/activate" 2>/dev/null)"
	set -e
	status="${reply##*$'\n'}"
	reply="${reply%$'\n'*}"

	case "$status" in
		200)
			if ! jq -e '.token and .driver.sha256' >/dev/null 2>&1 <<<"$reply"; then
				log "UPS $name: Tescom Connect gave an answer this add-on does not understand"
				status=000
			else
				jq --arg c "$code" '. + {code: $c}' <<<"$reply" >"$cache"
				model="$(jq -r '.model // empty' <<<"$reply")"
				log "UPS $name: activated (serial $serial${model:+, $model})"
			fi
			;;
		400|401|403|404|409|410)
			err="$(jq -r '.error // empty' <<<"$reply" 2>/dev/null || true)"
			rm -f "$cache"
			drop "$name" "Tescom Connect did not activate serial $serial: ${err:-refused (HTTP $status)}. $how"
			continue
			;;
	esac

	if [ "$status" != 200 ]; then
		# Tescom Connect cannot be reached: go on with the last activation, if it is still valid.
		if [ -s "$cache" ] && [ "$(jq -r '.code // ""' "$cache")" = "$code" ] \
			&& [ "$(jq -r '.expires_at // 0' "$cache")" -gt "$now" ]; then
			until="$(jq -r '.expires_at' "$cache")"
			log "UPS $name: Tescom Connect could not be reached (HTTP $status); using the activation kept here, valid until $(date -u -d "@$until" +%F 2>/dev/null || date -u -r "$until" +%F)"
			reply="$(cat "$cache")"
		else
			drop "$name" "Tescom Connect could not be reached (HTTP $status) to activate serial $serial; it is tried again at the next start"
			continue
		fi
	fi

	active+=("$name")
	token="$(jq -r '.token' <<<"$reply")"
	sha="$(jq -r '.driver.sha256' <<<"$reply" | tr 'A-F' 'a-f')"
done

[ "${#active[@]}" -gt 0 ] || exit 0

# The driver: the one kept in DATA if it is the one Tescom Connect names, else downloaded.
bin="$DATA/drivers/$ARCH/tescom_prime"
have=""
[ -f "$bin" ] && have="$(sha256sum "$bin" | cut -d' ' -f1)"
if [ "$have" != "$sha" ]; then
	log "Downloading the tescom_prime driver for $ARCH"
	set +e
	code="$(curl -sS -m 120 -H "Authorization: Bearer $token" -o "$bin.part" -w '%{http_code}' \
		"$CLOUD/addon/drivers/tescom_prime?arch=$ARCH" 2>/dev/null)"
	set -e
	got=""
	[ -f "$bin.part" ] && got="$(sha256sum "$bin.part" | cut -d' ' -f1)"
	if [ "$code" = 200 ] && [ "$got" = "$sha" ]; then
		chmod 0755 "$bin.part"
		mv -f "$bin.part" "$bin"
	else
		rm -f "$bin.part"
		if [ -n "$have" ]; then
			log "Could not download the new driver (HTTP $code); keeping the one already here"
		else
			for name in "${active[@]}"; do drop "$name" "the tescom_prime driver could not be downloaded (HTTP $code); it is tried again at the next start"; done
			exit 0
		fi
	fi
fi

if ! "$bin" -V >/dev/null 2>&1; then
	rm -f "$bin"
	for name in "${active[@]}"; do drop "$name" "the downloaded tescom_prime driver does not run here ($ARCH)"; done
	exit 0
fi
ln -sf "$bin" "$DRIVER_DIR/tescom_prime"
log "tescom_prime $("$bin" -V 2>&1 | sed -n 's/.* driver \([0-9.]*\)$/\1/p' | head -1) ready for: ${active[*]}"
