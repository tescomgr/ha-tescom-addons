#!/usr/bin/env bash
# Tests for tescom_nut/rootfs/usr/lib/tescom-nut/genconf.sh against a fake
# /sys and /dev: a Tescom Prime (CH340, 1a86:7523) on ttyUSB0 and an APC
# HID UPS (051d:0002). Needs bash and jq.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
GENCONF="$HERE/../tescom_nut/rootfs/usr/lib/tescom-nut/genconf.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/     /'; }

# Fake sysfs.
S="$T/sys"
usbdev() { # path vendor product [interface-class]
	mkdir -p "$S/devices/$1"
	echo "$2" >"$S/devices/$1/idVendor"
	echo "$3" >"$S/devices/$1/idProduct"
	mkdir -p "$S/bus/usb/devices"
	ln -s "../../../devices/$1" "$S/bus/usb/devices/$(basename "$1")"
	if [ -n "${4:-}" ]; then
		mkdir -p "$S/devices/$1/$(basename "$1"):1.0"
		echo "$4" >"$S/devices/$1/$(basename "$1"):1.0/bInterfaceClass"
	fi
}
usbdev pci0/usb1/1-1 1a86 7523
mkdir -p "$S/devices/pci0/usb1/1-1/1-1:1.0/ttyUSB0" "$S/class/tty/ttyUSB0"
ln -s "../../../devices/pci0/usb1/1-1/1-1:1.0/ttyUSB0" "$S/class/tty/ttyUSB0/device"

# Fake /dev.
D="$T/dev"
mkdir -p "$D/serial/by-id"
touch "$D/ttyUSB0"
ln -s ../../ttyUSB0 "$D/serial/by-id/usb-1a86_USB_Serial-if00-port0"

export SYSFS="$S" DEV="$D"

# run NAME OPTIONS_JSON -> output in $T/NAME/, exit code in $rc, stderr in $err
run() {
	mkdir -p "$T/$1"
	printf '%s' "$2" >"$T/$1/options.json"
	set +e
	err="$(bash "$GENCONF" "$T/$1/options.json" "$T/$1/etc" 2>&1)"
	rc=$?
	set -e
	conf="$T/$1/etc/ups.conf"
}
has() { grep -qxF -- "$2" "$1"; }

# 1. Blank driver and port: the Prime is found.
run blank '{"devices":[{"name":"ups","driver":"","port":"","config":[]}],"username":"homeassistant","password":"secret"}'
if [ "$rc" = 0 ] && has "$conf" "[ups]" && has "$conf" "  driver = tescom_prime" && has "$conf" "  port = $D/ttyUSB0"; then
	ok "blank device becomes tescom_prime on /dev/ttyUSB0"
else bad "blank device becomes tescom_prime on /dev/ttyUSB0" "$err"; fi

# 2. upsd.conf and upsd.users.
if has "$T/blank/etc/upsd.conf" "LISTEN 0.0.0.0 3493" \
	&& has "$T/blank/etc/upsd.users" "[homeassistant]" \
	&& has "$T/blank/etc/upsd.users" '  password = "secret"' \
	&& has "$T/blank/etc/upsd.users" "  upsmon primary"; then
	ok "upsd.conf listens on 3493, upsd.users has the user"
else bad "upsd.conf listens on 3493, upsd.users has the user"; fi

# 3. Two blank devices: the Prime, then a HID UPS.
usbdev pci0/usb1/1-2 051D 0002 03
run two '{"devices":[{"name":"prime","driver":"","port":""},{"name":"apc","driver":"","port":""}],"username":"u","password":"p"}'
if [ "$rc" = 0 ] && has "$conf" "  driver = usbhid-ups" && has "$conf" "  vendorid = 051d" \
	&& [ "$(grep -c 'driver = tescom_prime' "$conf")" = 1 ]; then
	ok "second blank device takes the HID UPS (usbhid-ups, vendorid 051d)"
else bad "second blank device takes the HID UPS" "$err$(cat "$conf" 2>/dev/null)"; fi

# 4. Port by id, driver blank: tescom_prime.
run byid "{\"devices\":[{\"name\":\"ups\",\"driver\":\"\",\"port\":\"$D/serial/by-id/usb-1a86_USB_Serial-if00-port0\"}],\"username\":\"u\",\"password\":\"p\"}"
if [ "$rc" = 0 ] && has "$conf" "  driver = tescom_prime" && has "$conf" "  port = $D/serial/by-id/usb-1a86_USB_Serial-if00-port0"; then
	ok "a /dev/serial/by-id port of a CH340 gets tescom_prime"
else bad "a /dev/serial/by-id port of a CH340 gets tescom_prime" "$err"; fi

# 5. Explicit driver and config lines are kept; LiON RT defaults added once.
run mec '{"devices":[{"name":"lionrt","driver":"nutdrv_qx_mec","port":"auto","config":["vendorid = 0001","protocol = megatec","lowbatt = 30"]}],"username":"u","password":"p"}'
if [ "$rc" = 0 ] && has "$conf" "  driver = nutdrv_qx_mec" && has "$conf" "  subdriver = krauler" \
	&& has "$conf" "  langid_fix = 0x0409" && has "$conf" "  lowbatt = 30" \
	&& [ "$(grep -c 'protocol' "$conf")" = 1 ]; then
	ok "nutdrv_qx_mec gets the LiON RT defaults, config lines kept"
else bad "nutdrv_qx_mec gets the LiON RT defaults, config lines kept" "$err$(cat "$conf" 2>/dev/null)"; fi

# 6. Prime config line.
run lowbatt '{"devices":[{"name":"ups","driver":"tescom_prime","port":"/dev/ttyUSB0","config":["lowbatt = 25"]}],"username":"u","password":"p"}'
if [ "$rc" = 0 ] && has "$conf" "  lowbatt = 25" && has "$conf" "  port = /dev/ttyUSB0"; then
	ok "explicit tescom_prime with lowbatt"
else bad "explicit tescom_prime with lowbatt" "$err"; fi

# 7. Failures.
expect_fail() { # name json message
	run "$1" "$2"
	if [ "$rc" != 0 ] && grep -qF -- "$3" <<<"$err"; then ok "refuses: $3"; else bad "refuses: $3" "rc=$rc $err"; fi
}
expect_fail nopass '{"devices":[{"name":"ups"}],"username":"u","password":""}' "set a password"
expect_fail nodev '{"devices":[],"username":"u","password":"p"}' "add at least one device"
expect_fail badname '{"devices":[{"name":"my ups"}],"username":"u","password":"p"}' "may only use letters"
expect_fail baddrv '{"devices":[{"name":"ups","driver":"rm -rf"}],"username":"u","password":"p"}' "unknown driver"
expect_fail quote '{"devices":[{"name":"ups"}],"username":"u","password":"a\"b"}' "may not contain"
expect_fail primeport '{"devices":[{"name":"ups","driver":"tescom_prime"}],"username":"u","password":"p"}' "needs a serial port"
expect_fail toomany '{"devices":[{"name":"a"},{"name":"b"},{"name":"c"}],"username":"u","password":"p"}' "device c: no UPS found"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
