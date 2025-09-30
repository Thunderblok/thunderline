# Build a Flower SuperExec image that bundles your ServerApp/ClientApp code
# Usage:
#   docker build -f superexec.Dockerfile --build-arg APP_SRC=. -t ghcr.io/thunderblok/flower-superexec:0.0.1 .
#   docker push ghcr.io/thunderblok/flower-superexec:0.0.1

ARG FLOWER_VERSION=1.22.0
FROM flwr/superexec:${FLOWER_VERSION}

# Directory inside the image where the Flower project will live
ARG APP_DIR=/workspace/app
# Build context path (relative to the location of your Flower project when building)
ARG APP_SRC=.

WORKDIR ${APP_DIR}

# Copy project metadata first to leverage Docker layer caching
COPY ${APP_SRC}/pyproject.toml ./

# Remove the flwr dependency from pyproject (already part of base image) and
# install remaining deps. The Thunderline repo’s `python/cerebros/keras` package
# will be installed as part of this step so the Keras backend is available.
RUN sed -i '/flwr\[[^]]*\]/d' pyproject.toml \
    && python -m pip install --no-cache-dir -U .

# Copy the rest of the application code
COPY ${APP_SRC}/ .

# Flower already ships the `flower-superexec` entrypoint
ENTRYPOINT ["flower-superexec"]
