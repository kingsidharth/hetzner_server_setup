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
RUN cd /tmp && curl -fsSLO "https://dl.google.com/android/repository/${CMDLINE_TOOLS}" \
    && echo "${CMDLINE_TOOLS_SHA1}  ${CMDLINE_TOOLS}" | sha1sum -c - \
    && unzip -q "$CMDLINE_TOOLS" && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && mv cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" && rm "$CMDLINE_TOOLS" \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0" \
      "ndk;27.1.12297006" "cmake;3.30.5" >/dev/null
# The entrypoint needs root to start; it drops to runner itself.
USER root
