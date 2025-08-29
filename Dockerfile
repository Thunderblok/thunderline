#############################################
# Thunderline Production/Demo Container
# Multi-stage build producing a minimal release image.
# Supports DEMO_MODE enabling CA viz & lineage features.
#############################################

ARG ELIXIR_VERSION=1.18.0
ARG OTP_VERSION=26.2.5
ARG ALPINE_VERSION=3.19
ARG APP_NAME=thunderline
ARG MIX_ENV=prod

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS build

ENV MIX_ENV=${MIX_ENV} \
    HEX_UNSAFE_HTTPS=1 \
    LANG=C.UTF-8

RUN apk add --no-cache build-base git nodejs npm python3 curl bash openssl ncurses-libs

WORKDIR /app

# Install hex/rebar
RUN mix local.hex --force && mix local.rebar --force

# Cache deps
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only ${MIX_ENV} && mix deps.compile

# Copy assets & source
COPY priv priv
COPY lib lib
COPY assets assets
COPY tailwind.config.js esbuild.config.js package.json tsconfig.json* ./ 2>/dev/null || true

# Precompile assets (Tailwind+esbuild) and release
RUN mix assets.deploy
RUN mix compile
RUN mix release

############################################################
FROM alpine:${ALPINE_VERSION} AS runtime
RUN apk add --no-cache openssl ncurses-libs libstdc++ bash
WORKDIR /app

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    REPLACE_OS_VARS=true \
    PHX_SERVER=true

# Copy release from build image
COPY --from=build /app/_build/prod/rel/${APP_NAME} ./

# Expose Phoenix port
EXPOSE 4000

# HEALTHCHECK (simple TCP check)
HEALTHCHECK --interval=30s --timeout=3s --retries=5 CMD nc -z localhost 4000 || exit 1

# Entrypoint wrapper: run migrations (unless SKIP_ASH_SETUP) then start release
COPY scripts/docker/dev_entrypoint.sh ./bin/dev_entrypoint.sh
RUN chmod +x ./bin/dev_entrypoint.sh

ENTRYPOINT ["/app/bin/${APP_NAME}"]
CMD ["start"]

# For demo mode (DEMO_MODE=1) recommendations:
#   - Set features via runtime env (see Feature module runtime override)
#   - Provide SECRET_KEY_BASE, DATABASE_URL, TOKEN_SIGNING_SECRET
