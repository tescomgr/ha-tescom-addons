# Tescom Connect API used by the add-on

The Tescom Prime's driver, `tescom_prime`, is not in this repository or its
images. Tescom Connect (`https://connect.tescom.gr/v1`) hands it to an add-on
whose user has registered the UPS on myTescom: the activation code myTescom
shows on the UPS's page is the proof. `tescom_nut/rootfs/usr/lib/tescom-nut/activate.sh`
is the client; `tests/mockcloud.py` is a stand-in server for the tests.

## `POST /v1/addon/activate`

No session. Rate-limited per IP and per serial.

Request (JSON):

| Field | |
| --- | --- |
| `serial` | The UPS's serial number, upper case, letters and digits only |
| `code` | The six-digit activation code from myTescom, digits only |
| `install_id` | A UUID the add-on makes once and keeps in `/data/install_id` |
| `arch` | `aarch64` or `x86_64` |
| `addon_version` | The add-on's version, e.g. `2.8.4-1` |

The server checks the code against the serial (as `/activations/code` does:
`activationCode(ACTIVATION_SECRET, serial)`), that the serial is a known
Tescom unit, and records the install (serial, install_id, arch, version,
first and last seen), so a code shared among many installs shows.

Answers:

- `200`:
  ```json
  {
    "token": "opaque, for the download",
    "expires_at": 1766000000,
    "model": "Prime 1102 XL",
    "driver": { "version": "0.04", "nut": "2.8.4", "sha256": "lowercase hex" }
  }
  ```
  `expires_at` (Unix seconds) is how long the add-on may go on without
  reaching Tescom Connect again; 30 days suggested. `model` is optional.
- `400` bad request, `403` wrong code, `404` not a Tescom serial, `409` or
  `410` refused for another reason (too many installs, revoked): each with
  `{"error": "a sentence for the user"}`, which the add-on logs as is.
- `429` and `5xx`: the add-on treats them as "cannot be reached" and goes on
  with a kept, unexpired activation.

## `GET /v1/addon/drivers/tescom_prime?arch=ARCH`

`Authorization: Bearer <token>`. Answers `200` with the binary
(`application/octet-stream`) whose SHA-256 is the one `activate` gave, or
`401` for a missing or expired token, `404` for an unknown arch.

The binaries are the ones nut-app's `scripts/build-nut.sh` builds on Linux
(`src-tauri/resources/nut/<target>/libexec/tescom_prime`, x86_64 and aarch64,
statically linked but for glibc), e.g. kept in R2 under
`addon/drivers/<nut version>/<arch>/tescom_prime` by the release workflow.
They run in the add-on as they are: the add-on sets `NUT_CONFPATH=/etc/nut`
and `NUT_STATEPATH=NUT_ALTPIDPATH=/run/nut`, so the paths built into them
(`/etc`, `/run`) do not matter. Tested with a `release/0.5` build on
2026-11-17.

## Licence

`tescom_prime` is built against NUT, so it is GPL-2.0-or-later: whoever
receives the binary is entitled to its source on request. Tescom Connect
gives it to activated users only; the source goes to them when asked.
