#!/usr/bin/env bash
# Write NUT's ups.conf, upsd.conf and upsd.users from the add-on options.
#
#   genconf.sh OPTIONS_JSON CONF_DIR
#
# Plain bash and jq, no bashio, so it can be tested outside Home Assistant.
# SYSFS (default /sys) and DEV (default /dev) can point elsewhere for tests.
#
# A device with a blank driver gets one from its USB ID:
#   1a86:7523 (CH340 USB-serial, Tescom Prime)  tescom_prime on that /dev/ttyUSB*
#   Megatec-style USB bridges                   nutdrv_qx, port auto
#   USB HID power devices of known UPS makers   usbhid-ups, port auto
# A device with a blank port and a blank driver takes the next UPS found.

set -euo pipefail

OPTIONS="${1:-/data/options.json}"
CONF="${2:-/etc/nut}"
SYSFS="${SYSFS:-/sys}"
DEV="${DEV:-/dev}"

log() { printf '[tescom-nut] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# USB vendor:product (lowercase hex) of the device a tty belongs to.
tty_usb_id() { # ttyUSB0
	local d
	d="$(readlink -f "$SYSFS/class/tty/$1/device" 2>/dev/null)" || return 1
	while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "$SYSFS" ]; do
		if [ -f "$d/idVendor" ] && [ -f "$d/idProduct" ]; then
			printf '%s:%s\n' "$(tr 'A-F' 'a-f' <"$d/idVendor")" "$(tr 'A-F' 'a-f' <"$d/idProduct")"
			return 0
		fi
		d="$(dirname "$d")"
	done
	return 1
}

# The kernel name (ttyUSB0) behind a port such as /dev/serial/by-id/usb-...
port_tty() {
	local p
	p="$(readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
	basename "$p"
}

PRIME_ID="1a86:7523"
# Megatec/Q1 USB bridges that nutdrv_qx speaks to (vendor:product).
QX_IDS=" 0665:5161 0001:0000 ffff:0000 06da:0003 0f03:0001 14f0:00c9 "
# Vendors whose USB HID power devices usbhid-ups knows.
HID_VENDORS=" 03f0 0463 047c 050d 051d 0592 05dd 06da 075d 0764 09ae 09d6 0d9f 10af 1cb0 2e51 2e66 "

# Candidate UPSs, in order: "driver|port|vendorid|productid".
CANDIDATES=()
discover() {
	local t id d v p cls
	for t in "$SYSFS"/class/tty/ttyUSB* "$SYSFS"/class/tty/ttyACM*; do
		[ -e "$t" ] || continue
		t="$(basename "$t")"
		id="$(tty_usb_id "$t")" || continue
		if [ "$id" = "$PRIME_ID" ]; then
			CANDIDATES+=("tescom_prime|$DEV/$t||")
			log "found $id on $DEV/$t: Tescom Prime (tescom_prime)"
		fi
	done
	for d in "$SYSFS"/bus/usb/devices/*; do
		[ -f "$d/idVendor" ] || continue
		v="$(tr 'A-F' 'a-f' <"$d/idVendor")"
		p="$(tr 'A-F' 'a-f' <"$d/idProduct")"
		if [[ "$QX_IDS" == *" $v:$p "* ]]; then
			CANDIDATES+=("nutdrv_qx|auto|$v|$p")
			log "found $v:$p: Megatec-style USB UPS (nutdrv_qx)"
			continue
		fi
		[[ "$HID_VENDORS" == *" $v "* ]] || continue
		# A HID interface (class 03) on this device.
		for cls in "$d"/*:*/bInterfaceClass; do
			[ -f "$cls" ] || continue
			if [ "$(cat "$cls")" = "03" ]; then
				CANDIDATES+=("usbhid-ups|auto|$v|$p")
				log "found $v:$p: USB HID UPS (usbhid-ups)"
				break
			fi
		done
	done
}

[ -f "$OPTIONS" ] || die "no options file at $OPTIONS"
jq -e . "$OPTIONS" >/dev/null || die "$OPTIONS is not JSON"

username="$(jq -r '.username // ""' "$OPTIONS")"
password="$(jq -r '.password // ""' "$OPTIONS")"
[ -n "$username" ] || die "set a username in the add-on options"
[ -n "$password" ] || die "set a password in the add-on options"
[[ "$username" =~ ^[A-Za-z0-9_.-]+$ ]] || die "username may only use letters, digits, _ . -"
case "$password" in *'"'*|*$'\n'*) die "the password may not contain \" or a line break" ;; esac

count="$(jq '.devices | length' "$OPTIONS")"
[ "$count" -gt 0 ] || die "add at least one device in the add-on options"

discover
used=()

mkdir -p "$CONF"
umask 027

{
	echo "# Written by the Tescom NUT add-on at start-up; edits are lost."
	echo "maxretry = 3"
	echo "retrydelay = 5"
	echo "pollinterval = 5"
} >"$CONF/ups.conf.new"

for ((i = 0; i < count; i++)); do
	name="$(jq -r ".devices[$i].name // \"\"" "$OPTIONS")"
	driver="$(jq -r ".devices[$i].driver // \"\"" "$OPTIONS")"
	port="$(jq -r ".devices[$i].port // \"\"" "$OPTIONS")"
	vendorid=""
	productid=""
	[[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || die "device name '$name' may only use letters, digits, _ . -"

	if [ -z "$driver" ]; then
		if [ -n "$port" ] && [ "$port" != "auto" ]; then
			# A serial port given: what is behind it?
			id="$(tty_usb_id "$(port_tty "$port")" || true)"
			if [ "$id" = "$PRIME_ID" ]; then
				driver="tescom_prime"
			else
				die "device $name: cannot tell the driver for $port (USB ID '${id:-unknown}'); set one"
			fi
		else
			# The next UPS found that no other device has taken.
			for c in "${CANDIDATES[@]+"${CANDIDATES[@]}"}"; do
				taken=""
				for u in "${used[@]+"${used[@]}"}"; do [ "$u" = "$c" ] && taken=1; done
				[ -z "$taken" ] || continue
				IFS='|' read -r driver port vendorid productid <<<"$c"
				used+=("$c")
				break
			done
			[ -n "$driver" ] || die "device $name: no UPS found on USB; check the cable, or set driver and port"
		fi
		log "device $name: $driver on $port${vendorid:+ ($vendorid:$productid)}"
	fi

	case "$driver" in
		tescom_prime|usbhid-ups|nutdrv_qx|nutdrv_qx_mec|blazer_usb|blazer_ser) ;;
		*) die "device $name: unknown driver '$driver'" ;;
	esac
	if [ -z "$port" ]; then
		case "$driver" in
			tescom_prime|blazer_ser) die "device $name: $driver needs a serial port, e.g. /dev/ttyUSB0" ;;
			*) port="auto" ;;
		esac
	fi

	{
		echo
		echo "[$name]"
		echo "  driver = $driver"
		echo "  port = $port"
		[ -z "$vendorid" ] || echo "  vendorid = $vendorid"
		[ -z "$productid" ] || echo "  productid = $productid"
		extra="$(jq -r ".devices[$i].config // [] | .[] | select(. != null and . != \"\")" "$OPTIONS")"
		if [ "$driver" = "nutdrv_qx_mec" ]; then
			# The Tescom LiON RT's MEC0003 bridge (nut-app deploy/README.md).
			for kv in "subdriver = krauler" "protocol = megatec" "langid_fix = 0x0409"; do
				grep -qE "^[[:space:]]*${kv%% *}[[:space:]]*=" <<<"$extra" || echo "  $kv"
			done
		fi
		[ -z "$extra" ] || sed 's/^/  /' <<<"$extra"
	} >>"$CONF/ups.conf.new"
done

cat >"$CONF/upsd.conf.new" <<EOF
# Written by the Tescom NUT add-on at start-up; edits are lost.
LISTEN 0.0.0.0 3493
LISTEN :: 3493
MAXAGE 25
EOF

cat >"$CONF/upsd.users.new" <<EOF
# Written by the Tescom NUT add-on at start-up; edits are lost.
[$username]
  password = "$password"
  actions = SET FSD
  instcmds = ALL
  upsmon primary
EOF

for f in ups.conf upsd.conf upsd.users; do
	mv -f "$CONF/$f.new" "$CONF/$f"
done
chmod 0640 "$CONF/upsd.users"
log "wrote $CONF/ups.conf, upsd.conf, upsd.users"
