# ci-windows: Windows desktop builds from Linux. electron-builder packages NSIS natively and
# uses Wine for exe resource editing; jsign signs Authenticode (incl. Azure Artifact Signing).
FROM ci-node:current

ARG JSIGN_VERSION=7.6
ARG JSIGN_SHA256=0fef4c11fde986d04134bd59d9bb241226170c84fd14c5285811ca27ee0c6dbc

RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends wine wine64 wine32:i386 xvfb xauth \
      openjdk-17-jre-headless osslsigncode \
    && cd /tmp && curl -fsSLO "https://github.com/ebourg/jsign/releases/download/${JSIGN_VERSION}/jsign_${JSIGN_VERSION}_all.deb" \
    && echo "${JSIGN_SHA256}  jsign_${JSIGN_VERSION}_all.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends "./jsign_${JSIGN_VERSION}_all.deb" \
    && rm -f /tmp/*.deb && rm -rf /var/lib/apt/lists/*

# A ready Wine prefix for the job user, so builds don't pay for (or hang on) first-run setup.
ENV WINEDEBUG=-all WINEARCH=win64 WINEPREFIX=/home/runner/.wine WINEDLLOVERRIDES="mscoree,mshtml="
RUN setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/runner wineboot --init \
    && setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/runner wineserver --wait
