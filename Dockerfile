# ================================
# Build image
# ================================
FROM swift:5.5.0-focal as build
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve

# Copy entire repo into container
COPY . .

RUN apt-get update -y && apt-get install -y wget

# Compile with optimizations
RUN swift build --enable-test-discovery -c release

CMD ["ls", "-a"]
