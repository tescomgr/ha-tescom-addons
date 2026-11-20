# shellcheck shell=bash
# Tescom's UPS profiles: the ups.conf settings that make each model work,
# taken from nut-app v0.6.0 (profiles/*.conf; crates/nut-identify/src/profiles.rs
# for how a reading is told apart). Sourced by genconf.sh and identify.sh.
#
# Every setting is one line, "key = value" or a bare flag. A key the device's
# own `config` lines already set is left out: the user's setting wins.

# The settings every Megatec/Q1 UPS on the 0001:0000 USB bridge needs with
# nutdrv_qx (Leo LCD, Leo SmartBox, Neoline): the bridge reports no USB
# strings, hence langid_fix, novendor and noscanlangid. nutdrv_qx reads the
# voltages only every pollfreq (30 s by default); every Q1 reply has them.
# shellcheck disable=SC2034 # used by genconf.sh
HUNNOX_BASE=(
	"subdriver = hunnox"
	"langid_fix = 0x0409"
	"novendor"
	"noscanlangid"
	"pollfreq = 2"
)

# The model's own settings, added once it is known. $1 is the profile key.
profile_settings() {
	case "$1" in
		leo)
			printf '%s\n' \
				'desc = "Tescom Leo LCD"' \
				'override.ups.mfr = Tescom' 'override.ups.model = "Leo LCD"' \
				'override.device.mfr = Tescom' 'override.device.model = "Leo LCD"'
			;;
		smartbox)
			printf '%s\n' \
				'desc = "Tescom Leo SmartBox"' \
				'override.ups.mfr = Tescom' 'override.ups.model = "Leo SmartBox"' \
				'override.device.mfr = Tescom' 'override.device.model = "Leo SmartBox"'
			;;
		neoline)
			printf '%s\n' \
				'protocol = megatec' \
				'battery_voltage_reports_one_pack' \
				'override.battery.packs = 12' \
				'default.battery.voltage.high = 26.0' \
				'default.battery.voltage.low = 20.8' \
				'desc = "Tescom Neoline"' \
				'override.ups.mfr = Tescom' 'override.ups.model = Neoline' \
				'override.device.mfr = Tescom' 'override.device.model = Neoline'
			;;
		lion)
			# LiON RT 1 kVA: 8 x 3.2 V LiFePO4; Q1 reports 1/48th of the pack voltage.
			printf '%s\n' \
				'subdriver = krauler' \
				'protocol = megatec' \
				'langid_fix = 0x0409' \
				'noscanlangid' \
				'novendor' \
				'override.input.voltage.nominal = 230' \
				'override.input.frequency.nominal = 50' \
				'override.input.current.nominal = 4.0' \
				'pollinterval = 2' \
				'pollfreq = 2' \
				'battery_voltage_reports_one_pack' \
				'override.battery.packs = 48' \
				'override.battery.voltage.nominal = 25.6' \
				'default.battery.voltage.low = 24.0' \
				'default.battery.voltage.high = 26.8' \
				'desc = "Tescom LiON"' \
				'override.ups.mfr = Tescom' 'override.ups.model = LiON' \
				'override.device.mfr = Tescom' 'override.device.model = LiON'
			;;
		prime)
			# The driver reports make and model itself.
			printf '%s\n' 'pollinterval = 2' 'desc = "Tescom Prime"'
			;;
	esac
}

# Which hunnox model a running driver's reading is: upsc's "name: value"
# lines on stdin. Neoline is the on-line one; the Leo LCD has a 24 V pack,
# the SmartBox a 12 V battery. Prints nothing when it cannot tell.
profile_from_reading() {
	awk -F': ' '
		$1 == "ups.type" { type = tolower($2) }
		$1 == "battery.voltage.nominal" { nominal = $2 + 0 }
		END {
			if (type == "online") print "neoline"
			else if (nominal == 24) print "leo"
			else if (nominal == 12) print "smartbox"
		}'
}

# The key of a ups.conf line: "a" for "a = b", "a=b" and the flag "a".
conf_key() {
	local k="${1%%=*}"
	k="${k#"${k%%[![:space:]]*}"}"
	printf '%s' "${k%"${k##*[![:space:]]}"}"
}

# A ups.conf line with its value quoted when it needs to be: a value with a
# space, a quote, a backslash, a # or a = is cut short or misread otherwise.
# A value already in double quotes is kept as it is.
conf_line() {
	local line="$1" key value special='[[:space:]"\#=]' quoted='^".*"$'
	case "$line" in *=*) ;; *) conf_key "$line"; echo; return ;; esac
	key="$(conf_key "$line")"
	value="${line#*=}"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	if [[ ${#value} -ge 2 && "$value" =~ $quoted ]]; then
		:
	elif [[ "$value" =~ $special ]]; then
		value="${value//\\/\\\\}"
		value="\"${value//\"/\\\"}\""
	fi
	printf '%s = %s\n' "$key" "$value"
}

# The lines of $2 (one per line) whose keys $1 (one ups.conf line per line,
# the user's) does not set, indented and quoted.
settings_not_in() {
	local user="$1" line
	local -A have=()
	while IFS= read -r line; do
		[ -n "$line" ] && have["$(conf_key "$line")"]=1
	done <<<"$user"
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		[ -n "${have[$(conf_key "$line")]:-}" ] || printf '  %s\n' "$(conf_line "$line")"
	done <<<"$2"
}
