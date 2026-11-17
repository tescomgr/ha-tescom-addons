#!/usr/bin/env bash
# Tests for tescom_nut/rootfs/usr/lib/tescom-nut/activate.sh against
# tests/mockcloud.py, with a stand-in driver. Needs bash, jq, curl, python3,
# sha256sum (run it in the add-on image, or on Linux).

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ACTIVATE="$HERE/../tescom_nut/rootfs/usr/lib/tescom-nut/activate.sh"
T="$(mktemp -d)"
PORT="${PORT:-18765}"
mkdir -p "$T/cloud" "$T/drv"
printf '#!/bin/sh\necho "Network UPS Tools 2.8.4 release - Tescom Prime (Modbus) driver 0.04"\n' >"$T/cloud/tescom_prime"
python3 "$HERE/mockcloud.py" "$PORT" "$T/cloud/tescom_prime" >"$T/cloud.log" 2>&1 &
cloud=$!
trap 'kill $cloud 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do curl -s "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break; sleep 0.1; done

export TESCOM_CLOUD="http://127.0.0.1:$PORT/v1" NUT_DRIVER_DIR="$T/drv" ARCH=aarch64 ADDON_VERSION=test

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/     /'; }

# run CASE OPTIONS_JSON: a fresh ups.conf with a Prime "prime" and an APC "apc"; DATA kept per CASE
run() {
	mkdir -p "$T/$1/etc" "$T/$1/data"
	printf '%s' "$2" >"$T/$1/options.json"
	printf 'maxretry = 3\n\n[prime]\n  driver = tescom_prime\n  port = /dev/ttyUSB0\n\n[apc]\n  driver = usbhid-ups\n  port = auto\n' >"$T/$1/etc/ups.conf"
	set +e
	err="$(bash "$ACTIVATE" "$T/$1/options.json" "$T/$1/etc" "$T/$1/data" 2>&1)"
	rc=$?
	set -e
	conf="$T/$1/etc/ups.conf"
}
good='{"devices":[{"name":"prime","serial":"prime-0001","activation_code":"123 456"},{"name":"apc"}]}'

# 1. Right code: activated, driver downloaded, linked, both UPSs kept.
rm -f "$T/drv/tescom_prime"
run good "$good"
if [ "$rc" = 0 ] && grep -qx '\[prime\]' "$conf" && grep -qx '\[apc\]' "$conf" \
	&& [ -x "$T/good/data/drivers/aarch64/tescom_prime" ] && [ -L "$T/drv/tescom_prime" ] \
	&& grep -q 'activated (serial PRIME0001, Prime 1102 XL)' <<<"$err"; then
	ok "right code: activated, driver downloaded and linked"
else bad "right code: activated, driver downloaded and linked" "rc=$rc $err"; fi
if grep -q '"install_id"' "$T/cloud.log" && grep -q '"code": "123456"' "$T/cloud.log" && grep -q 'Bearer tok-PRIME0001' "$T/cloud.log"; then
	ok "the request carries serial, code, install_id; the download the token"
else bad "the request carries serial, code, install_id; the download the token" "$(cat "$T/cloud.log")"; fi

# 2. Second start: no second download.
n="$(grep -c '^GET' "$T/cloud.log")"
run good "$good"
if [ "$rc" = 0 ] && [ "$(grep -c '^GET' "$T/cloud.log")" = "$n" ] && grep -qx '\[prime\]' "$conf"; then
	ok "second start: driver kept, not downloaded again"
else bad "second start: driver kept, not downloaded again" "$err"; fi

# 3. Cloud down: the kept activation is used.
touch "$T/cloud/down"
run good "$good"
rm -f "$T/cloud/down"
if [ "$rc" = 0 ] && grep -qx '\[prime\]' "$conf" && grep -q 'using the activation kept here' <<<"$err"; then
	ok "cloud down: the kept activation is used"
else bad "cloud down: the kept activation is used" "$err"; fi

# 4. Cloud down and never activated: left out, the APC kept.
touch "$T/cloud/down"
run fresh "$good"
rm -f "$T/cloud/down"
if [ "$rc" = 0 ] && ! grep -qx '\[prime\]' "$conf" && grep -qx '\[apc\]' "$conf" && grep -q 'could not be reached' <<<"$err"; then
	ok "cloud down, never activated: Prime left out, APC kept"
else bad "cloud down, never activated: Prime left out, APC kept" "$err$(cat "$conf")"; fi

# 5. Wrong code: left out, and the kept activation is forgotten.
run good '{"devices":[{"name":"prime","serial":"PRIME0001","activation_code":"111111"},{"name":"apc"}]}'
if ! grep -qx '\[prime\]' "$conf" && grep -qx '\[apc\]' "$conf" && grep -q 'wrong activation code' <<<"$err" \
	&& [ ! -e "$T/good/data/activation/PRIME0001.json" ]; then
	ok "wrong code: Prime left out with the cloud's reason, activation forgotten"
else bad "wrong code: Prime left out with the cloud's reason, activation forgotten" "$err"; fi

# 6. Unknown serial.
run unknown '{"devices":[{"name":"prime","serial":"XYZ","activation_code":"123456"},{"name":"apc"}]}'
if ! grep -qx '\[prime\]' "$conf" && grep -q 'not a Tescom UPS' <<<"$err" && grep -q 'my.tescom.gr' <<<"$err"; then
	ok "unknown serial: left out, says to register on myTescom"
else bad "unknown serial: left out, says to register on myTescom" "$err"; fi

# 7. No serial or code given.
run blank '{"devices":[{"name":"prime"},{"name":"apc"}]}'
if ! grep -qx '\[prime\]' "$conf" && grep -qx '\[apc\]' "$conf" && grep -q 'needs activating' <<<"$err" \
	&& ! grep -q 'POST.*"serial": ""' "$T/cloud.log"; then
	ok "no serial or code: left out without asking the cloud"
else bad "no serial or code: left out without asking the cloud" "$err"; fi

# 8. A tampered driver in DATA is replaced.
echo junk >"$T/good/data/drivers/aarch64/tescom_prime"
run good "$good"
if grep -qx '\[prime\]' "$conf" && grep -q 'Tescom Prime (Modbus) driver 0.04' "$T/good/data/drivers/aarch64/tescom_prime"; then
	ok "a driver that is not the one named is downloaded again"
else bad "a driver that is not the one named is downloaded again" "$err"; fi

# 9. No Prime in ups.conf: nothing asked.
n="$(wc -l <"$T/cloud.log")"
mkdir -p "$T/noprime/etc" "$T/noprime/data"
printf '[apc]\n  driver = usbhid-ups\n  port = auto\n' >"$T/noprime/etc/ups.conf"
echo '{"devices":[{"name":"apc"}]}' >"$T/noprime/options.json"
if bash "$ACTIVATE" "$T/noprime/options.json" "$T/noprime/etc" "$T/noprime/data" && [ "$(wc -l <"$T/cloud.log")" = "$n" ]; then
	ok "no Prime: Tescom Connect is not contacted"
else bad "no Prime: Tescom Connect is not contacted"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
