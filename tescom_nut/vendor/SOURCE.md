# Vendored files

Tescom's patches to NUT, copied from Tescom Connect (`nut-app`, branch
`release/0.5`, 2026-11-17). Both are applied to NUT 2.8.4 by the Dockerfile,
the way nut-app's `scripts/build-nut.sh` applies them.

| File | What |
| --- | --- |
| `nutdrv_qx-hunnox-battery-test.patch` | The Leo SmartBox's quick battery test in `nutdrv_qx` (hunnox subdriver); applied before NUT is built, so `nutdrv_qx` and `nutdrv_qx_mec` have it |
| `nutdrv_qx-krauler-102-byte-reads.patch` | 102-byte reads for the LiON RT's MEC0003 bridge; built as `nutdrv_qx_mec` |

The Tescom Prime's driver is not here: see `docs/CLOUD-API.md`.
Both patches are under NUT's licence, GPL-2.0-or-later.
