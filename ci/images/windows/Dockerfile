# ci-windows: Windows desktop builds from Linux. electron-builder packages NSIS natively and
# uses Wine for exe resource editing; jsign signs Authenticode (incl. Azure Artifact Signing);
# makemsix packs Microsoft Store MSIX packages (electron-builder's appx target needs makeappx.exe).

# makemsix from a pinned microsoft/msix-packaging commit, with pack and schema validation. It needs
# clang, ICU headers and CMake 3.29+ (Ubuntu 24.04 ships 3.28, so CMake comes from Kitware, verified).
FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55 AS makemsix
ARG MSIX_REF=25a65f5c1690930813bcc10cdf1d59fa865f2bb1
ARG CMAKE_VERSION=3.31.6
ARG CMAKE_SHA256=5a1133ff103c71eb5120e2cc3de922733e7d8a26a98ae716397e8676adb367bf
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git make clang libicu-dev python3 \
    && cd /tmp && f="cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" \
    && curl -fsSLO "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/${f}" \
    && echo "${CMAKE_SHA256}  ${f}" | sha256sum -c - && tar -xzf "$f" -C /opt && rm "$f" \
    && git init -q /src && git -C /src fetch -q --depth 1 https://github.com/microsoft/msix-packaging "${MSIX_REF}" \
    && git -C /src checkout -q FETCH_HEAD \
    && "/opt/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake" -S /src -B /build -DCMAKE_BUILD_TYPE=MinSizeRel \
      -DCMAKE_TOOLCHAIN_FILE=/src/cmake/linux.cmake -DLINUX=on -DMSIX_PACK=on -DUSE_VALIDATION_PARSER=on \
      -DMSIX_SAMPLES=off -DMSIX_TESTS=off \
    && make -C /build -j"$(nproc)"

FROM ci-node:current

ARG JSIGN_VERSION=7.6
ARG JSIGN_SHA256=0fef4c11fde986d04134bd59d9bb241226170c84fd14c5285811ca27ee0c6dbc

RUN dpkg --add-architecture i386 && apt-get update \
    && apt-get install -y --no-install-recommends wine wine64 wine32:i386 xvfb xauth \
      openjdk-17-jre-headless osslsigncode libicu74 \
    && cd /tmp && curl -fsSLO "https://github.com/ebourg/jsign/releases/download/${JSIGN_VERSION}/jsign_${JSIGN_VERSION}_all.deb" \
    && echo "${JSIGN_SHA256}  jsign_${JSIGN_VERSION}_all.deb" | sha256sum -c - \
    && apt-get install -y --no-install-recommends "./jsign_${JSIGN_VERSION}_all.deb" \
    && rm -f /tmp/*.deb && rm -rf /var/lib/apt/lists/*

# A ready Wine prefix for the job user, so builds don't pay for (or hang on) first-run setup.
ENV WINEDEBUG=-all WINEARCH=win64 WINEPREFIX=/home/runner/.wine WINEDLLOVERRIDES="mscoree,mshtml="
RUN setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/runner wineboot --init \
    && setpriv --reuid=1001 --regid=1001 --init-groups env HOME=/home/runner wineserver --wait

COPY --from=makemsix /build/bin/makemsix /usr/local/bin/makemsix
COPY --from=makemsix /build/lib/libmsix.so /usr/local/lib/libmsix.so
RUN ldconfig && makemsix pack '-?' >/dev/null
