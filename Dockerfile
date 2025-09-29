#############################################
# Thunderline Production/Demo Container
# Multi-stage build producing a minimal release image.
# Supports DEMO_MODE enabling CA viz & lineage features.
#############################################

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=28.1
ARG DEBIAN_BUILD_REVISION=bookworm-20250908-slim
ARG DEBIAN_RUNTIME=bookworm-slim
ARG APP_NAME=thunderline
ARG MIX_ENV=prod

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_BUILD_REVISION} AS build
ARG MIX_ENV
ARG APP_NAME

ENV DEBIAN_FRONTEND=noninteractive \
    MIX_ENV=${MIX_ENV} \
    HEX_UNSAFE_HTTPS=1 \
    LANG=C.UTF-8 \
    TAILWIND_VERSION=3.4.14

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    nodejs \
    npm \
    python3 \
    python3-pip \
    curl \
    bash \
    openssl \
    libstdc++6 \
    libncursesw6 \
    libtinfo6 \
    ca-certificates \
    pkg-config \
        cmake \
    zlib1g-dev \
    libssl-dev \
    libffi-dev \
            unzip \
  && rm -rf /var/lib/apt/lists/*

ENV PATH="/root/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --profile minimal --default-toolchain stable

WORKDIR /app

# Install hex/rebar
RUN mix local.hex --force && mix local.rebar --force

# Cache deps
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only ${MIX_ENV}
RUN python3 - <<'PY'
from pathlib import Path
import shutil

prod_docker = Path("deps/prod_docker")
if prod_docker.exists():
    shutil.rmtree(prod_docker)

# Patch Jido InMemory adapter to tolerate missing metadata
target = Path("deps/jido/lib/jido/bus/adapters/in_memory.ex")
original = """    %Signal{\n      id: correlation_id,\n      source: causation_id,\n      type: type,\n      data: data,\n      jido_metadata: jido_metadata\n    } = signal\n\n    %RecordedSignal{\n      signal_id: Jido.Util.generate_id(),\n      signal_number: signal_number,\n      stream_id: stream_id,\n      stream_version: stream_version,\n      causation_id: causation_id,\n      correlation_id: correlation_id,\n      type: type,\n      data: data,\n      jido_metadata: jido_metadata,\n      created_at: now\n    }\n"""

replacement = """    %Signal{\n      id: correlation_id,\n      source: causation_id,\n      type: type,\n      data: data\n    } = signal\n\n    jido_metadata = Map.get(signal, :jido_metadata, %{})\n\n    %RecordedSignal{\n      signal_id: Jido.Util.generate_id(),\n      signal_number: signal_number,\n      stream_id: stream_id,\n      stream_version: stream_version,\n      causation_id: causation_id,\n      correlation_id: correlation_id,\n      type: type,\n      data: data,\n      jido_metadata: jido_metadata || %{},\n      created_at: now\n    }\n"""

text = target.read_text()
if original not in text:
    raise SystemExit("expected snippet not found in jido in_memory adapter")

target.write_text(text.replace(original, replacement))

PY
RUN mix deps.compile

# Copy assets & source
COPY priv priv
COPY lib lib
COPY assets assets
COPY tailwind.config.js package.json tsconfig.json* ./
COPY native native
RUN npm ci --prefix assets

# Precompile assets (Tailwind+esbuild) and release
RUN mix assets.deploy
RUN mix compile
RUN mix release

############################################################
FROM debian:${DEBIAN_RUNTIME} AS runtime
ARG APP_NAME
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        bash \
        openssl \
        libstdc++6 \
        libncursesw6 \
        libtinfo6 \
        tzdata \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    REPLACE_OS_VARS=true \
    PHX_SERVER=true \
    # OpenTelemetry exporter configuration (set at runtime if using OTLP)
    OTEL_SERVICE_NAME=thunderline \
    OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# Optional OTLP endpoints (uncomment and set via env in deployment if needed)
# ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
# ENV OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector:4318/v1/traces

# Copy release from build image
COPY --from=build /app/_build/prod/rel/${APP_NAME} ./

# Create non-root user and set ownership (for writable dirs like var/log)
RUN addgroup -S app && adduser -S app -G app && \
    mkdir -p /app/var && chown -R app:app /app
USER app

# Expose Phoenix port
EXPOSE 4000

# HEALTHCHECK (simple TCP check)
HEALTHCHECK --interval=30s --timeout=3s --retries=5 CMD nc -z localhost 4000 || exit 1

# Entrypoint wrapper: run migrations (unless SKIP_ASH_SETUP) then start release
COPY scripts/docker/dev_entrypoint.sh ./bin/dev_entrypoint.sh
RUN chmod +x ./bin/dev_entrypoint.sh

# Use exec form; expand app name at build time
ENTRYPOINT ["/app/bin/thunderline"]
CMD ["start"]

# For demo mode (DEMO_MODE=1) recommendations:
#   - Set features via runtime env (see Feature module runtime override)
#   - Provide SECRET_KEY_BASE, DATABASE_URL, TOKEN_SIGNING_SECRET
