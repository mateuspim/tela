# Toolchain for tela: Flutter + Android SDK, pinned.
#
# The host carries no Flutter and no Android SDK — everything (analyze, test,
# build, adb) runs in here, so a green build on this box means a green build
# anywhere. Versions are pinned, never `latest`: a silent Flutter bump is a
# silent Dart-SDK bump, and that breaks package resolution without touching
# a single line of our code.
#
# Fully qualified because Podman, unlike Docker, won't assume docker.io for a
# short name when no registries.conf alias exists.
FROM docker.io/library/eclipse-temurin:17-jdk

ARG FLUTTER_VERSION=3.44.6
ARG ANDROID_API=36
ARG BUILD_TOOLS=36.0.0
ARG CMDLINE_TOOLS=11076708
# Flutter's Gradle plugin pins these three and will silently sdkmanager-install
# them mid-build if they are missing. In a --rm container that download is
# thrown away and paid again on every single build, so they are baked in.
# compileSdk resolves to 35 (flutter.compileSdkVersion), not our targetSdk 36.
ARG COMPILE_API=35
ARG NDK=28.2.13676358
ARG CMAKE=3.22.1
# Match the invoking user so files written into the bind-mounted repo
# (pubspec.lock, .dart_tool/, android/) come back out owned by you, not root.
ARG UID=1000
ARG GID=1000

ENV ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/home/dev/.pub-cache \
    DEBIAN_FRONTEND=noninteractive

ENV PATH="${FLUTTER_ROOT}/bin:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PUB_CACHE}/bin:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git unzip zip xz-utils ca-certificates \
        # libGLU: the Flutter tool links it even for headless builds.
        libglu1-mesa \
        # usb + udev: adb talking to a physical device over the mounted USB bus.
        libusb-1.0-0 udev \
        # libsqlite3: `flutter test` runs Drift on the host VM, where there is no
        # sqlite3_flutter_libs to ship the native library the way there is on Android.
        # -dev, not -0: dart:ffi opens the unversioned `libsqlite3.so`, and only the
        # dev package ships that symlink.
        libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# The base image already ships a user at uid 1000; evict it so `dev` can own
# that uid and the bind-mounted repo stays writable from both sides.
RUN existing="$(getent passwd "${UID}" | cut -d: -f1)" \
    && if [ -n "$existing" ]; then userdel -r "$existing" 2>/dev/null || true; fi \
    && groupadd -f -g "${GID}" dev \
    && useradd -m -u "${UID}" -g "${GID}" -s /bin/bash dev

# --- Android SDK -----------------------------------------------------------
RUN mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && curl -fsSL -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS}_latest.zip" \
    && unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_SDK_ROOT}/cmdline-tools" \
    && mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" "${ANDROID_SDK_ROOT}/cmdline-tools/latest" \
    && rm /tmp/cmdline-tools.zip

RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install \
        "platform-tools" \
        "platforms;android-${ANDROID_API}" \
        "platforms;android-${COMPILE_API}" \
        "build-tools;${BUILD_TOOLS}" \
        "ndk;${NDK}" \
        "cmake;${CMAKE}" \
    > /dev/null

# --- Flutter ---------------------------------------------------------------
RUN curl -fsSL -o /tmp/flutter.tar.xz \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

RUN chown -R dev:dev "${FLUTTER_ROOT}" "${ANDROID_SDK_ROOT}"

USER dev
WORKDIR /app

# These three are bind targets for named volumes. A named volume inherits owner
# and content from the image path it covers — but only if that path exists.
# Without this, Docker creates them root-owned and Gradle cannot write its lock.
#
# .android holds the debug signing keystore. It has to outlive the container:
# Gradle mints a fresh debug.keystore whenever it finds none, a differently
# signed APK cannot update an installed one (INSTALL_FAILED_UPDATE_INCOMPATIBLE),
# and `flutter run` resolves that by uninstalling first — silently wiping app
# data, which is to say the Keystore-backed API key and the Drift database, on
# every single run.
RUN mkdir -p /home/dev/.gradle /home/dev/.pub-cache /home/dev/.android

# Flutter shells out to git against its own checkout; a bind-mounted repo owned
# by a different uid makes git refuse the directory outright.
RUN git config --global --add safe.directory "${FLUTTER_ROOT}" \
    && git config --global --add safe.directory /app

# Warm the tool's own caches (the Dart snapshot build) so the first real
# command in a container isn't a two-minute cold start.
RUN flutter config --no-analytics --android-sdk "${ANDROID_SDK_ROOT}" \
    && flutter precache --android --no-ios --no-linux --no-web \
    && flutter --version

CMD ["bash"]
