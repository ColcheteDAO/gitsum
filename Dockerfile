# ---------------------------------------------------
# Stage 1: Cargo Chef Planner
# ---------------------------------------------------
# UPDATED: Using floating slim-bookworm tag to ensure 
# the latest Rust compiler is used for cargo-chef compatibility.
FROM rust:slim-bookworm AS chef
USER root
RUN cargo install cargo-chef
WORKDIR /app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

# ---------------------------------------------------
# Stage 2: Caching and Building Dependencies
# ---------------------------------------------------
FROM chef AS builder
# Install native C-dependencies required by libgit2 and libssh2
RUN apt-get update && apt-get install -y \
    pkg-config libssl-dev libssh2-1-dev cmake build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY --from=planner /app/recipe.json recipe.json

# Build dependencies - this layer is cached by Docker!
RUN cargo chef cook --release --recipe-path recipe.json

# Build the actual application
COPY . .
RUN cargo build --release

# ---------------------------------------------------
# Stage 3: Minimal Runtime Environment
# ---------------------------------------------------
FROM debian:bookworm-slim

# Install the runtime shared libraries needed by the compiled binary
RUN apt-get update && apt-get install -y \
    libssh2-1 libssl3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the compiled binary from the builder stage
COPY --from=builder /app/target/release/grig /usr/local/bin/grig

# Expose the port your Axum server runs on
EXPOSE 3000

# Run the binary
ENTRYPOINT ["grig"]
