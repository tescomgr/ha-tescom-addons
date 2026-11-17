# End-to-end test without a UPS, Home Assistant or Tescom Connect

- `fakeprime.py` answers on a pty like a Tescom Prime online. It holds the
  Prime's register map, so it is not in this repository: copy it here from
  Tescom (nut-app) before building the test image. `.gitignore` keeps it out.
- `mocksup.py` answers the Supervisor API calls bashio makes (options, add-on
  info, discovery).
- `../mockcloud.py` stands in for Tescom Connect: it activates serial
  `PRIME0001` with code `123456` and serves a `tescom_prime` binary. Use one
  built by nut-app's `scripts/build-nut.sh` on Linux for the image's arch
  (`src-tauri/resources/nut/<target>/libexec/tescom_prime`).

From the repository root, with that binary in `$DRIVER_DIR`:

```bash
docker buildx build --platform linux/arm64 -t tescom-nut:dev --load tescom_nut
docker build -t tescom-nut:e2e -f tests/e2e/Dockerfile tests/e2e
docker network create nutnet
docker run -d --name mocksup --network nutnet --network-alias supervisor \
  -v "$PWD/tests/e2e":/e2e --entrypoint python3 tescom-nut:e2e -u /e2e/mocksup.py /e2e/options.json
docker run -d --name mockcloud --network nutnet --network-alias mockcloud \
  -v "$PWD/tests":/t:ro -v "$DRIVER_DIR":/drv --entrypoint python3 tescom-nut:e2e \
  -u /t/mockcloud.py 8080 /drv/tescom_prime
docker run -d --name nut-e2e --network nutnet -e SUPERVISOR_TOKEN=x \
  -v "$PWD/tests/e2e/options.json":/data/options.json:ro tescom-nut:e2e
docker exec nut-e2e upsc prime@localhost      # ups.status: OL CHRG
docker logs nut-e2e | grep tescom-nut         # activated, driver downloaded
docker logs mocksup                           # POST /discovery {"service":"nut",...}
docker rm -f nut-e2e mocksup mockcloud; docker network rm nutnet
```
