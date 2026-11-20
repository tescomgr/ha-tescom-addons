# Tescom NUT

Shows your Tescom UPS in Home Assistant: plug its USB cable into the Home
Assistant machine and the add-on finds it. Works with:

- **Tescom Prime** series, once the UPS is registered on myTescom (see
  below).
- **Tescom LiON RT**.
- **Tescom Leo SmartBox**, including its quick battery test.
- Most other USB UPSs (APC, Eaton, CyberPower and others).

Home Assistant's built-in **Network UPS Tools** integration then shows the
UPS's status, battery and load, and can run its tests.

## Installation

1. **Tescom Prime only:** register the UPS on [myTescom](https://my.tescom.gr)
   (its serial number is on the label). Its page there shows a six-digit
   **activation code**.
2. Plug the UPS's USB cable into the Home Assistant machine.
3. Settings > Add-ons > Add-on store > ⋮ > Repositories: add
   `https://github.com/tescomgr/ha-tescom-addons`.
4. Install **Tescom NUT**.
5. Configuration tab: set a **password** (and the username, if you like).
   For a Prime, fill in the device's **serial** and **activation code**.
   Leave driver and port blank to detect the UPS.
6. Start the add-on and check its log:

   ```text
   [tescom-nut] found a Tescom Prime on /dev/ttyUSB0
   [tescom-nut] UPS ups: activated (serial ..., Prime 1102 XL)
   [tescom-nut] Downloading the Tescom Prime driver for aarch64
   ```

7. Settings > Devices & services: Home Assistant shows **Network UPS Tools
   (NUT)** as discovered. Click Configure and enter:
   - Host: `localhost` (or the add-on's hostname, from its Info tab)
   - Port: `3493`
   - Username and password: the ones from step 5.

   No card? Add it by hand: **Add integration** > **Network UPS Tools
   (NUT)**, with the same host, port, username and password. Home Assistant
   shows only one NUT card at a time, and none once a NUT server is set up:
   another NUT card (often an old or unreachable NUT server on your network)
   hides this add-on's. Ignore that card, restart the add-on, and its card
   appears.

## Tescom Leo SmartBox, Leo LCD and Neoline

Nothing to configure: leave `driver`, `port` and `config` blank. The three
share one USB chip, so the add-on starts the UPS with the settings they have
in common, reads it, tells the model from its battery (12 V: SmartBox, 24 V:
Leo LCD) or its type (on-line: Neoline), and restarts it once with that
model's settings and its name. The log says:

```text
[tescom-nut] UPS ups: identified as Tescom Leo SmartBox; restarting its driver with that model's settings
```

The model is remembered, so later starts use its settings at once.

These UPSs do not report their battery charge: NUT estimates it from the
battery voltage. On mains the battery is kept above "full", so the charge
reads 100% until the UPS has been on battery for a while; treat it as a
rough guide.

## Sensors in Home Assistant

The integration adds the main sensors (status, battery charge, load, input
voltage). Others, such as battery voltage and temperature, are created
disabled. To show them: Settings > Devices & services > Network UPS Tools >
the UPS's device > the **Entities** list (or the integration's
**Entities** tab), select the ones you want, then **Enable selected**.

## Activation (Tescom Prime)

The Prime's driver is not part of the add-on: Tescom Connect gives it to
UPSs registered on myTescom. On start the add-on sends the serial number and
activation code to Tescom Connect (`connect.tescom.gr`), with a random ID for
this installation, and downloads the driver once. Nothing else is sent: no
readings, no other data about your home.

- The activation is kept for 30 days, so the UPS keeps working while the
  internet is down. The add-on checks again at each start.
- A wrong code or an unregistered serial leaves the Prime out, with the
  reason in the log. Other UPSs are not affected.
- Other Tescom and other brands' UPSs need no activation.

## Configuration

```yaml
devices:
  - name: ups
    driver: ""
    port: ""
    serial: "the serial number on the UPS's label"
    activation_code: "123456"
    config: []
username: homeassistant
password: "a long password"
```

### `devices`

One entry per UPS. `name` is the UPS's NUT name (`ups@localhost`).

- `driver` and `port` blank: the add-on picks the next UPS it finds on USB.
  A Tescom Prime (`1a86:7523`) gets `tescom_prime` on its `/dev/ttyUSB*`;
  UPSs with a Megatec USB bridge get `nutdrv_qx`; USB HID UPSs of known
  makes (APC, Eaton, CyberPower, ...) get `usbhid-ups`.
- `port` only: for a serial port that is a Tescom Prime, `tescom_prime`.
  `/dev/serial/by-id/...` names work too and stay the same across reboots.
- `driver` and `port` both set: used as given.
- `serial` and `activation_code`: a Tescom Prime's, from myTescom.
- `config`: extra `ups.conf` lines for this UPS, e.g. `lowbatt = 30`.
  A setting given here replaces the add-on's own for that key. Values with
  spaces are fine as they are: the add-on quotes them
  (`override.ups.model = My UPS`).

Tescom LiON RT (its USB chip is the same as the Leo's, so it needs setting
by hand):

```yaml
devices:
  - name: lionrt
    driver: nutdrv_qx_mec
    port: auto
    config:
      - vendorid = 0001
      - productid = 0000
```

The add-on adds the LiON's settings (`subdriver = krauler`, `protocol =
megatec`, its battery pack, make and model) unless `config` sets them.

### `tescom_prime` settings

- `lowbatt = N`: the battery charge (%) at or below which the UPS reports
  low battery (`LB`) on battery. Default 20. Home Assistant and NUT clients
  that shut down on low battery act on this.

The driver reads the UPS every 5 seconds: status (online, on battery,
bypass, off, charging), input, output and battery voltage, frequencies,
battery charge, run time on battery, load, power and temperature.
Instant commands:

- `beeper.enable`, `beeper.disable`, `beeper.mute`, `beeper.toggle`
- `test.battery.start.quick`, `test.battery.start` (minutes, default 1),
  `test.battery.start.deep` (to low battery), `test.battery.stop`
- `load.off` and `load.on`: `load.off` cuts the output **at once**, with no
  delay, so it also cuts Home Assistant if the UPS powers it.

NUT's shutdown (`upsdrvctl shutdown`, killpower) is not supported: the only
off command known cuts the output immediately.

### `log_level`

`debug` or `trace` run the drivers and `upsd` with debug output.

## When the driver does not start

The add-on tries again every 30 seconds, so a UPS switched on later is
picked up. If the log keeps saying `No Modbus reply on /dev/ttyUSB0`:

- the UPS is off, or the cable is not in the UPS's USB port;
- the UPS is not a Prime (set the driver by hand);
- another add-on has the port open (only one program can use a serial port:
  stop the other NUT add-on).

## Licence

GPL-2.0-or-later, like NUT itself. The `tescom_prime` driver is GPL too:
its source is available from Tescom to anyone who has received it.
