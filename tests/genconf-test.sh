#!/usr/bin/env bash
# Tests for tescom_nut/rootfs/usr/lib/tescom-nut/genconf.sh against a fake
# /sys and /dev: a Tescom Prime (CH340, 1a86:7523) on ttyUSB0 and an APC
# HID UPS (051d:0002), later a Leo/SmartBox bridge (0001:0000); identify.sh
# with a stand-in upsc. Needs bash and jq.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../tescom_nut/rootfs/usr/lib/tescom-nut"
GENCONF="$LIB/genconf.sh"
IDENTIFY="$LIB/identify.sh"
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
	err="$(bash "$GENCONF" "$T/$1/options.json" "$T/$1/etc" "$T/$1/data" 2>&1)"
	rc=$?
	set -e
	conf="$T/$1/etc/ups.conf"
}
has() { grep -qxF -- "$2" "$1"; }
count() { grep -cxF -- "$2" "$1" || true; }

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
	if has "$conf" "  override.battery.packs = 48" && has "$conf" '  desc = "Tescom LiON"' \
		&& has "$conf" "  override.ups.mfr = Tescom" && [ "$(count "$conf" "  vendorid = 0001")" = 1 ]; then
		ok "nutdrv_qx_mec gets the LiON profile (packs, description, make)"
	else bad "nutdrv_qx_mec gets the LiON profile" "$(cat "$conf")"; fi
else bad "nutdrv_qx_mec gets the LiON RT defaults, config lines kept" "$err$(cat "$conf" 2>/dev/null)"; fi

# 6. Prime config line.
run lowbatt '{"devices":[{"name":"ups","driver":"tescom_prime","port":"/dev/ttyUSB0","config":["lowbatt = 25"]}],"username":"u","password":"p"}'
if [ "$rc" = 0 ] && has "$conf" "  lowbatt = 25" && has "$conf" "  port = /dev/ttyUSB0"; then
	ok "explicit tescom_prime with lowbatt"
	if has "$conf" "  pollinterval = 2" && has "$conf" '  desc = "Tescom Prime"'; then
		ok "tescom_prime gets the Prime profile"
	else bad "tescom_prime gets the Prime profile" "$(cat "$conf")"; fi
else bad "explicit tescom_prime with lowbatt" "$err"; fi

# 7. A Leo/SmartBox bridge, found as the third blank device.
usbdev pci0/usb1/1-3 0001 0000
three='{"devices":[{"name":"prime"},{"name":"apc"},{"name":"leo"}],"username":"u","password":"p"}'
run leo "$three"
section() { awk -v n="[$2]" '/^\[.*\]$/ { in_it = ($0 == n) } in_it' "$1"; }
sec="$(section "$conf" leo)"
if [ "$rc" = 0 ] && grep -qxF "  driver = nutdrv_qx" <<<"$sec" && grep -qxF "  vendorid = 0001" <<<"$sec" \
	&& grep -qxF "  subdriver = hunnox" <<<"$sec" && grep -qxF "  langid_fix = 0x0409" <<<"$sec" \
	&& grep -qxF "  novendor" <<<"$sec" && grep -qxF "  noscanlangid" <<<"$sec" \
	&& grep -qxF "  # Tescom profile: unknown" <<<"$sec" && ! grep -q "override.ups.model" <<<"$sec" \
	&& has "$T/leo/etc/identify" "leo"; then
	ok "0001:0000 gets nutdrv_qx with the hunnox settings, listed for identification"
else bad "0001:0000 gets nutdrv_qx with the hunnox settings" "$err$sec"; fi

# 8. The model found last time is used at once.
mkdir -p "$T/cached/data/models"
echo smartbox >"$T/cached/data/models/leo"
run cached "$three"
sec="$(section "$conf" leo)"
if [ "$rc" = 0 ] && grep -qxF '  desc = "Tescom Leo SmartBox"' <<<"$sec" \
	&& grep -qxF '  override.ups.model = "Leo SmartBox"' <<<"$sec" && grep -qxF '  override.device.mfr = Tescom' <<<"$sec" \
	&& grep -qxF "  # Tescom profile: smartbox" <<<"$sec"; then
	ok "a cached SmartBox gets its profile (make, model in quotes) at once"
else bad "a cached SmartBox gets its profile at once" "$err$sec"; fi

# 9. The user's settings win; values with spaces and quotes are quoted.
mkdir -p "$T/user/data/models"
echo smartbox >"$T/user/data/models/box"
run user '{"devices":[{"name":"box","driver":"nutdrv_qx","port":"auto","config":["vendorid = 0001","productid = 0000","subdriver=hunnox","override.ups.model = My Box","desc = say \"hi\"","novendor"]}],"username":"u","password":"p"}'
sec="$(section "$conf" box)"
if [ "$rc" = 0 ] && [ "$(grep -c 'subdriver' <<<"$sec")" = 1 ] && [ "$(grep -c 'novendor' <<<"$sec")" = 1 ] \
	&& [ "$(grep -c 'vendorid' <<<"$sec")" = 1 ] \
	&& grep -qxF '  override.ups.model = "My Box"' <<<"$sec" && [ "$(grep -c 'override.ups.model' <<<"$sec")" = 1 ] \
	&& grep -qxF '  desc = "say \"hi\""' <<<"$sec" && [ "$(grep -c 'desc' <<<"$sec")" = 1 ] \
	&& grep -qxF '  override.device.model = "Leo SmartBox"' <<<"$sec"; then
	ok "config lines win over the profile, values with spaces or quotes are quoted"
else bad "config lines win over the profile, values quoted" "$err$sec"; fi

# 10. identify.sh, with a stand-in upsc.
cat >"$T/upsc" <<'SH'
#!/usr/bin/env bash
[ -s "$READING" ] || exit 1
cat "$READING"
SH
chmod +x "$T/upsc"
export UPSC="$T/upsc" READING="$T/reading"
run ident "$three"
cp "$conf" "$T/ident/before"
identify() { set +e; ierr="$(bash "$IDENTIFY" leo "$T/ident/options.json" "$T/ident/etc" "$T/ident/data" 2>&1)"; irc=$?; set -e; sec="$(section "$conf" leo)"; }
: >"$READING"
identify
if [ "$irc" = 1 ] && cmp -s "$conf" "$T/ident/before"; then ok "identify: no reading yet, try again (1)"; else bad "identify: no reading yet" "$irc $ierr"; fi
printf 'battery.voltage.nominal: 12.0\nups.type: offline / line interactive\n' >"$READING"
identify
if [ "$irc" = 10 ] && grep -qxF '  override.ups.model = "Leo SmartBox"' <<<"$sec" \
	&& grep -qxF "  # Tescom profile: smartbox" <<<"$sec" && [ "$(cat "$T/ident/data/models/leo")" = smartbox ] \
	&& [ "$(grep -c 'Tescom profile' <<<"$sec")" = 1 ] && has "$conf" "[apc]" && has "$conf" "  driver = usbhid-ups"; then
	ok "identify: 12 V nominal is a SmartBox, profile written, restart asked (10)"
else bad "identify: 12 V nominal is a SmartBox" "$irc $ierr$sec"; fi
identify
if [ "$irc" = 0 ]; then ok "identify: same model again, nothing to do (0)"; else bad "identify: same model again" "$irc $ierr"; fi
printf 'battery.voltage.nominal: 24\n' >"$READING"
identify
if [ "$irc" = 10 ] && grep -qxF '  override.ups.model = "Leo LCD"' <<<"$sec" && ! grep -q SmartBox <<<"$sec" \
	&& [ "$(grep -c 'subdriver' <<<"$sec")" = 1 ]; then
	ok "identify: 24 V nominal is a Leo LCD, the SmartBox settings replaced"
else bad "identify: 24 V nominal is a Leo LCD" "$irc $ierr$sec"; fi
printf 'battery.voltage.nominal: 24\nups.type: online\n' >"$READING"
identify
if [ "$irc" = 10 ] && grep -qxF '  override.battery.packs = 12' <<<"$sec" && grep -qxF '  desc = "Tescom Neoline"' <<<"$sec" \
	&& ! grep -q 'Leo' <<<"$sec"; then
	ok "identify: an on-line UPS is a Neoline"
else bad "identify: an on-line UPS is a Neoline" "$irc $ierr$sec"; fi
printf 'battery.voltage.nominal: 36\n' >"$READING"
cp "$conf" "$T/ident/before"
identify
if [ "$irc" = 0 ] && cmp -s "$conf" "$T/ident/before" && grep -q "not a Tescom model" <<<"$ierr"; then
	ok "identify: an unknown reading changes nothing"
else bad "identify: an unknown reading changes nothing" "$irc $ierr"; fi

# 11. Failures.
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
expect_fail toomany '{"devices":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"}],"username":"u","password":"p"}' "device d: no UPS found"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
