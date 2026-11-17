FROM tescom-nut:dev
RUN apt-get update -qq && apt-get install -y -qq python3 >/dev/null && rm -rf /var/lib/apt/lists/*
COPY fakeprime.py /fakeprime.py
RUN mkdir -p /etc/s6-overlay/s6-rc.d/fakeprime /etc/s6-overlay/s6-rc.d/init-nut/dependencies.d \
 && echo longrun > /etc/s6-overlay/s6-rc.d/fakeprime/type \
 && printf '#!/bin/sh\nrm -f /dev/ttyFAKE\nexec python3 /fakeprime.py /dev/ttyFAKE\n' > /etc/s6-overlay/s6-rc.d/fakeprime/run \
 && chmod +x /etc/s6-overlay/s6-rc.d/fakeprime/run \
 && touch /etc/s6-overlay/user-bundles.d/user/contents.d/fakeprime /etc/s6-overlay/s6-rc.d/init-nut/dependencies.d/fakeprime
