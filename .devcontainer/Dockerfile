# We're using a Swift nightly image here because Swift 6.0 stable doesn't support Strings on embedded platforms yet, but the `main` branch does.
FROM --platform=linux/arm64 swiftlang/swift:nightly-jammy@sha256:259791e6ffb3de34ef81bf8da098fb3ffa15d091b1b7f29b39f144c90633aa12

# Install CMake 3.29, which isn't available in the default repository.
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget software-properties-common gpg-agent && \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $(. /etc/os-release && echo $VERSION_CODENAME) main" | tee /etc/apt/sources.list.d/kitware.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends cmake ninja-build && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
