# Tescom Home Assistant add-ons

Home Assistant add-ons (apps) for Tescom UPSs.

| Add-on | What it does |
| --- | --- |
| [Tescom NUT](tescom_nut/) | Network UPS Tools 2.8.4 for Tescom UPSs plugged by USB into Home Assistant (Green, Yellow, or any aarch64/amd64 HA OS box), so they show up in the built-in Network UPS Tools integration. A Tescom Prime is supported once it is registered on [myTescom](https://my.tescom.gr). |

## Install

0. Tescom Prime: register it on [myTescom](https://my.tescom.gr) and note the
   activation code its page shows.
1. In Home Assistant: **Settings > Add-ons > Add-on store**.
2. **⋮ > Repositories**, add this URL, then **Add**:

   ```text
   https://github.com/tescomgr/ha-tescom-addons
   ```

3. Find **Tescom NUT** in the store, **Install**.
4. In its **Configuration** tab set a password (and, for a Prime, its serial
   number and activation code), then **Start**.
5. **Settings > Devices & services**: configure the discovered
   **Network UPS Tools (NUT)** with host `localhost`, port `3493` and the
   username and password from step 4.

The add-on's [documentation](tescom_nut/DOCS.md) has the details.

Do not run this add-on and the community NUT add-on on the same UPS: only one
of them can open its port.

## Why not the community NUT add-on?

The Tescom Prime's USB port is a CH340 USB-serial chip (`1a86:7523`) that
stock NUT cannot read (`nutdrv_qx` gets `read: timeout`). Its driver,
`tescom_prime`, is Tescom's own and is not in this repository: the add-on
downloads it from Tescom Connect once the UPS is activated with its myTescom
code ([docs/CLOUD-API.md](docs/CLOUD-API.md)).

## Building locally

```bash
docker buildx build --platform linux/arm64 -t tescom-nut:dev tescom_nut
```

Use `linux/amd64` for an Intel/AMD box. CI (`.github/workflows/`) builds both
architectures with `home-assistant/builder` and pushes them to
`ghcr.io/tescomgr/tescom-nut` on every push to `main`.

The repository and the images must be public: Home Assistant adds add-on
repositories and pulls their images without signing in. After the first push,
check that the `tescom-nut`, `aarch64-tescom-nut` and `amd64-tescom-nut`
packages under the `tescomgr` organisation are public (Package settings >
Change visibility).

`tescom_nut/rootfs/usr/lib/tescom-nut/genconf.sh` writes NUT's configuration
and `activate.sh` activates a Prime; both can be tried outside Home
Assistant (the second needs Linux, or the add-on image):

```bash
tests/genconf-test.sh
tests/activate-test.sh
```

`tests/e2e/` runs the whole add-on with a fake Prime, a mock Supervisor and a
mock Tescom Connect.

## Sources and credits

- [Network UPS Tools](https://networkupstools.org/) 2.8.4, GPL-2.0-or-later,
  downloaded and built in the Dockerfile.
- `tescom_nut/vendor/`: Tescom's NUT patches for the LiON RT and the Leo
  SmartBox; [SOURCE.md](tescom_nut/vendor/SOURCE.md) names their source.
- The add-on layout follows Home Assistant's
  [apps-example](https://github.com/home-assistant/apps-example) and the
  community [NUT add-on](https://github.com/hassio-addons/addon-nut) (MIT).
  No code was copied from the community add-on.

## Licence

GPL-2.0-or-later: see [LICENSE](LICENSE). The NUT drivers built into the image
are NUT derivatives and are distributed under the same terms. So is
`tescom_prime`, which Tescom distributes to activated users; its source is
available from Tescom to anyone who has received it.
