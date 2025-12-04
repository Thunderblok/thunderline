# Thunderline Development Container
# Full development environment with Elixir, Node, Python, and all dev tools

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.1
ARG DEBIAN_VERSION=bookworm-20250908-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}

ENV DEBIAN_FRONTEND=noninteractive \
    MIX_ENV=dev \
    LANG=C.UTF-8 \
    HEX_UNSAFE_HTTPS=1

# Install system dependencies for development
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build essentials
    build-essential \
    git \
    curl \
    wget \
    bash \
    # SSL and crypto
    openssl \
    ca-certificates \
    libssl-dev \
    # Node.js and npm
    nodejs \
    npm \
    # Python for ML/NLP services
    python3 \
    python3-pip \
    python3-venv \
    # Native compilation deps
    pkg-config \
    cmake \
    zlib1g-dev \
    libffi-dev \
    # Runtime libs
    libstdc++6 \
    libncursesw6 \
    libtinfo6 \
    # Postgres client for DB access
    postgresql-client \
    # Utilities
    unzip \
    inotify-tools \
    procps \
    htop \
    less \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Rust (needed for some native deps like Rustler NIFs)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Set working directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Pre-create directories for volume mounts
RUN mkdir -p /app/deps /app/_build /app/node_modules

# Default command keeps container alive for VS Code to attach
CMD ["sleep", "infinity"]
