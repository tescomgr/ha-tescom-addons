# Network UPS Tools with Tescom's own drivers, for Home Assistant.
#
# Stage 1 builds NUT from its release tarball the way Tescom Connect's
# scripts/build-nut.sh does on Linux (nut-app release/0.5): libusb built here,
# statically and without udev, so the programs need only glibc; plus:
#   - nutdrv_qx with vendor/nutdrv_qx-hunnox-battery-test.patch (Leo SmartBox)
#   - nutdrv_qx_mec: nutdrv_qx with vendor/nutdrv_qx-krauler-102-byte-reads.patch
# Stage 2 is the Home Assistant Debian base with only the results.
#
# The Tescom Prime's driver, tescom_prime, is not in this image: the add-on
# downloads it from Tescom Connect once the UPS is activated with its
# myTescom activation code (rootfs/usr/lib/tescom-nut/activate.sh).
#
# Local build (BuildKit): docker buildx build --platform linux/arm64 tescom_nut

ARG BUILD_FROM=ghcr.io/home-assistant/base-debian:trixie

# --------------------------------------------------------------------------
FROM ${BUILD_FROM} AS build

ARG NUT_VERSION=2.8.4
ARG LIBUSB_VERSION=1.0.27
ARG DRIVERS="usbhid-ups,nutdrv_qx,blazer_usb,blazer_ser"

RUN \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        bzip2 \
        pkg-config \
        patch \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/libusb
RUN \
    curl -fsSL --retry 3 -o /tmp/libusb.tar.bz2 \
        "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2" \
    && tar -xjf /tmp/libusb.tar.bz2 --strip-components 1 \
    && rm /tmp/libusb.tar.bz2 \
    && CFLAGS="-O2 -fPIC" ./configure --prefix=/usr/src/deps \
        --disable-shared --enable-static --disable-udev \
    && make -j"$(nproc)" \
    && make install

ENV PKG_CONFIG_PATH=/usr/src/deps/lib/pkgconfig

WORKDIR /usr/src/nut
RUN \
    curl -fsSL --retry 3 -o /tmp/nut.tar.gz \
        "https://networkupstools.org/source/${NUT_VERSION%.*}/nut-${NUT_VERSION}.tar.gz" \
    && tar -xzf /tmp/nut.tar.gz --strip-components 1 \
    && rm /tmp/nut.tar.gz

COPY vendor/ /usr/src/vendor/

# The hunnox battery test (Tescom Leo SmartBox), before the build, so both
# nutdrv_qx and nutdrv_qx_mec have it.
RUN patch -p1 --forward < /usr/src/vendor/nutdrv_qx-hunnox-battery-test.patch

# The add-on runs as root, in its own container, with the UPS's device passed in.
RUN \
    CFLAGS="-O2" ./configure \
        --prefix=/usr \
        --sysconfdir=/etc/nut \
        --with-statepath=/run/nut \
        --with-altpidpath=/run/nut \
        --with-drvpath=/usr/lib/nut \
        --with-user=root --with-group=root \
        --with-drivers="${DRIVERS}" \
        --with-usb=libusb-1.0 --with-serial \
        --with-usb-includes="-I/usr/src/deps/include/libusb-1.0" \
        --with-usb-libs="-L/usr/src/deps/lib -lusb-1.0 -lpthread" \
        --disable-shared --enable-static \
        --with-doc=no --without-dev --without-cgi --without-snmp --without-neon \
        --without-nss --with-ssl=no --without-avahi --without-powerman \
        --without-modbus --without-ipmi --without-wrap --without-libltdl \
        --without-nut-scanner --without-nutconf \
    && make -j"$(nproc)" \
    && make DESTDIR=/stage install

# nutdrv_qx_mec: the LiON RT's MEC0003 bridge needs 102-byte reads.
RUN \
    patch -p1 --forward < /usr/src/vendor/nutdrv_qx-krauler-102-byte-reads.patch \
    && make -C drivers nutdrv_qx \
    && install -m 0755 drivers/nutdrv_qx /stage/usr/lib/nut/nutdrv_qx_mec

# Only what the add-on uses.
RUN \
    mkdir -p /out/usr/bin /out/usr/sbin /out/usr/lib/nut \
    && for p in upsc upscmd upsrw; do cp "$(find /stage -name "$p" -type f | head -1)" /out/usr/bin/; done \
    && for p in upsd upsmon upsdrvctl; do cp "$(find /stage -name "$p" -type f | head -1)" /out/usr/sbin/; done \
    && for d in usbhid-ups nutdrv_qx nutdrv_qx_mec blazer_usb blazer_ser; do \
        cp "/stage/usr/lib/nut/$d" /out/usr/lib/nut/; \
    done \
    && mkdir -p /out/usr/share \
    && cp /stage/usr/share/cmdvartab /out/usr/share/ \
    && echo "${NUT_VERSION}" > /out/usr/lib/nut/NUT_VERSION

# Nothing but glibc: libusb was linked statically (as build-nut.sh checks).
RUN \
    for f in /out/usr/bin/* /out/usr/sbin/* /out/usr/lib/nut/*; do \
        [ -x "$f" ] || continue; \
        if ldd "$f" | awk '{print $1}' | grep -vE '^(linux-vdso|/lib/ld-linux|/lib64/ld-linux|ld-linux|libc\.so|libm\.so|libpthread\.so|libdl\.so|librt\.so|libresolv\.so)' | grep -q .; then \
            echo "$f links to a library beyond glibc:"; ldd "$f"; exit 1; \
        fi; \
    done

# --------------------------------------------------------------------------
FROM ${BUILD_FROM}

COPY --from=build /out/ /
COPY rootfs /

RUN chmod a+x \
    /etc/s6-overlay/s6-rc.d/*/run \
    /etc/s6-overlay/s6-rc.d/*/up \
    /etc/s6-overlay/s6-rc.d/*/finish \
    /usr/lib/tescom-nut/*.sh \
    2>/dev/null || true

# Drivers built elsewhere (tescom_prime, built by Tescom Connect with
# --with-statepath=/run and --sysconfdir=/etc) find this layout from these.
ENV \
    PATH="/usr/lib/nut:${PATH}" \
    NUT_CONFPATH="/etc/nut" \
    NUT_STATEPATH="/run/nut" \
    NUT_ALTPIDPATH="/run/nut"

LABEL \
    org.opencontainers.image.title="Home Assistant App: Tescom NUT" \
    org.opencontainers.image.description="Network UPS Tools 2.8.4 for Tescom UPSs; the Tescom Prime's driver after activation" \
    org.opencontainers.image.source="https://github.com/tescomgr/ha-tescom-addons" \
    org.opencontainers.image.licenses="GPL-2.0-or-later"
