# Tescom NUT

Network UPS Tools (NUT) 2.8.4 for Home Assistant, with Tescom's own drivers:

- `tescom_prime` for the **Tescom Prime** series, once the UPS is registered
  on myTescom (see below). The Prime's USB port is a serial port (a CH340
  chip, USB ID `1a86:7523`, `/dev/ttyUSB0`) that stock NUT drivers cannot
  read: the community NUT add-on only gets `read: timeout` from it.
- `nutdrv_qx_mec` for the **Tescom LiON RT** (nutdrv_qx with a fix for its
  USB bridge).
- `nutdrv_qx` with the quick battery test added for the **Tescom Leo
  SmartBox** (hunnox subdriver), which stock NUT lacks.
- The stock `usbhid-ups`, `blazer_usb` and `blazer_ser` for other UPSs.

The add-on runs the driver and the NUT server (`upsd`) on port 3493. Home
Assistant's built-in **Network UPS Tools** integration reads the UPS from it.

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
   [tescom-nut] found 1a86:7523 on /dev/ttyUSB0: Tescom Prime (tescom_prime)
   [tescom-nut] UPS ups: activated (serial ..., Prime 1102 XL)
   [tescom-nut] Downloading the tescom_prime driver for aarch64
   ```

7. Settings > Devices & services: Home Assistant shows **Network UPS Tools
   (NUT)** as discovered. Click Configure and enter:
   - Host: `localhost` (or the add-on's hostname, from its Info tab)
   - Port: `3493`
   - Username and password: the ones from step 5.

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

Tescom LiON RT:

```yaml
devices:
  - name: lionrt
    driver: nutdrv_qx_mec
    port: auto
    config:
      - vendorid = 0001
      - productid = 0000
```

The add-on adds `subdriver = krauler`, `protocol = megatec` and
`langid_fix = 0x0409` unless `config` sets them.

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
