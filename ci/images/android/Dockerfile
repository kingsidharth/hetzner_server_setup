# ci-android: Expo / React Native Android builds (prebuild + Gradle). The SDK is owned by the
# job user, so Gradle can fetch any extra platform or NDK a project pins. Gradle's own cache
# lives on the GRADLE_USER_HOME volume (see ci-node).
FROM ci-node:current

ARG CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG CMDLINE_TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60

ENV ANDROID_HOME=/opt/android-sdk ANDROID_SDK_ROOT=/opt/android-sdk \
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends openjdk-17-jdk-headless ninja-build cmake \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o runner -g runner "$ANDROID_HOME"

USER runner
# Abort and retry stalled transfers: some dl.google.com IPv4 anycast addresses accept TCP but
# never send data from this host, and a retry usually resolves to a working one.
RUN cd /tmp && curl -fsSLO --speed-limit 10240 --speed-time 30 --retry 8 --retry-all-errors \
      "https://dl.google.com/android/repository/${CMDLINE_TOOLS}" \
    && echo "${CMDLINE_TOOLS_SHA1}  ${CMDLINE_TOOLS}" | sha1sum -c - \
    && unzip -q "$CMDLINE_TOOLS" && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && mv cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" && rm "$CMDLINE_TOOLS" \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0" \
      "build-tools;35.0.0" "ndk;27.1.12297006" "cmake;3.30.5" "cmake;3.22.1" >/dev/null
# build-tools 35 and CMake 3.22.1 are what React Native 0.86 / Expo 57 builds ask for. Without
# them AGP downloads them in every fresh container, and that download can stall the build.
# The entrypoint needs root to start; it drops to runner itself.
USER root
