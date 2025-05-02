### Creates a storage Docker image with postgres, pageserver, safekeeper and proxy binaries.
### The image itself is mainly used as a container for the binaries and for starting e2e tests with custom parameters.
### By default, the binaries inside the image have some mock parameters and can start, but are not intended to be used
### inside this image in the real deployments.
ARG REPOSITORY=ghcr.io/neondatabase
ARG IMAGE=build-tools
ARG TAG=pinned
ARG DEFAULT_PG_VERSION=17
ARG STABLE_PG_VERSION=16

# Build Postgres
FROM $REPOSITORY/$IMAGE:$TAG AS pg-build
WORKDIR /home/nonroot

COPY --chown=nonroot vendor/postgres-v14 vendor/postgres-v14
COPY --chown=nonroot vendor/postgres-v15 vendor/postgres-v15
COPY --chown=nonroot vendor/postgres-v16 vendor/postgres-v16
COPY --chown=nonroot vendor/postgres-v17 vendor/postgres-v17
COPY --chown=nonroot pgxn pgxn
COPY --chown=nonroot Makefile Makefile
COPY --chown=nonroot scripts/ninstall.sh scripts/ninstall.sh

ENV BUILD_TYPE=release
RUN set -e \
    && mold -run make -j $(nproc) -s neon-pg-ext \
    && rm -rf pg_install/build \
    && tar -C pg_install -czf /home/nonroot/postgres_install.tar.gz .

# Prepare cargo-chef recipe
FROM $REPOSITORY/$IMAGE:$TAG AS plan
WORKDIR /home/nonroot

COPY --chown=nonroot . .

RUN cargo chef prepare --recipe-path recipe.json

# Build neon binaries
FROM $REPOSITORY/$IMAGE:$TAG AS build
WORKDIR /home/nonroot
ARG GIT_VERSION=local
ARG BUILD_TAG
ARG STABLE_PG_VERSION

COPY --from=pg-build /home/nonroot/pg_install/v14/include/postgresql/server pg_install/v14/include/postgresql/server
COPY --from=pg-build /home/nonroot/pg_install/v15/include/postgresql/server pg_install/v15/include/postgresql/server
COPY --from=pg-build /home/nonroot/pg_install/v16/include/postgresql/server pg_install/v16/include/postgresql/server
COPY --from=pg-build /home/nonroot/pg_install/v17/include/postgresql/server pg_install/v17/include/postgresql/server
COPY --from=pg-build /home/nonroot/pg_install/v16/lib                       pg_install/v16/lib
COPY --from=pg-build /home/nonroot/pg_install/v17/lib                       pg_install/v17/lib
COPY --from=plan     /home/nonroot/recipe.json                              recipe.json

ARG ADDITIONAL_RUSTFLAGS=""

RUN set -e \
    && RUSTFLAGS="-Clinker=clang -Clink-arg=-fuse-ld=mold -Clink-arg=-Wl,--no-rosegment -Cforce-frame-pointers=yes ${ADDITIONAL_RUSTFLAGS}" cargo chef cook --locked --release --recipe-path recipe.json

COPY --chown=nonroot . .

RUN set -e \
    && RUSTFLAGS="-Clinker=clang -Clink-arg=-fuse-ld=mold -Clink-arg=-Wl,--no-rosegment -Cforce-frame-pointers=yes ${ADDITIONAL_RUSTFLAGS}" cargo build \
      --bin pg_sni_router  \
      --bin pageserver  \
      --bin pagectl  \
      --bin safekeeper  \
      --bin storage_broker  \
      --bin storage_controller  \
      --bin proxy  \
      --bin endpoint_storage \
      --bin neon_local \
      --bin storage_scrubber \
      --locked --release

# Build final image
#
FROM debian:bookworm-slim
ARG DEFAULT_PG_VERSION
WORKDIR /data

RUN set -e \
    && echo 'Acquire::Retries "5";' > /etc/apt/apt.conf.d/80-retries \
    && apt update \
    && apt install -y \
        libreadline-dev \
        libseccomp-dev \
        ca-certificates \
	# System postgres for use with client libraries (e.g. in storage controller)
        postgresql-15 \
        openssl \
        curl \
        netcat-openbsd \
    && rm -f /etc/apt/apt.conf.d/80-retries \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && useradd -d /data neon \
    && chown -R neon:neon /data

COPY --from=build --chown=neon:neon /home/nonroot/target/release/pg_sni_router       /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/pageserver          /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/pagectl             /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/safekeeper          /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/storage_broker      /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/storage_controller  /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/proxy               /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/endpoint_storage    /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/neon_local          /usr/local/bin
COPY --from=build --chown=neon:neon /home/nonroot/target/release/storage_scrubber    /usr/local/bin

COPY --from=pg-build /home/nonroot/pg_install/v14 /usr/local/v14/
COPY --from=pg-build /home/nonroot/pg_install/v15 /usr/local/v15/
COPY --from=pg-build /home/nonroot/pg_install/v16 /usr/local/v16/
COPY --from=pg-build /home/nonroot/pg_install/v17 /usr/local/v17/
COPY --from=pg-build /home/nonroot/postgres_install.tar.gz /data/

# By default, pageserver uses `.neon/` working directory in WORKDIR, so create one and fill it with the dummy config.
# Now, when `docker run ... pageserver` is run, it can start without errors, yet will have some default dummy values.
RUN mkdir -p /data/.neon/ && \
  echo "id=1234" > "/data/.neon/identity.toml" && \
  echo "broker_endpoint='http://storage_broker:50051'\n" \
       "pg_distrib_dir='/usr/local/'\n" \
       "listen_pg_addr='0.0.0.0:6400'\n" \
       "listen_http_addr='0.0.0.0:9898'\n" \
       "availability_zone='local'\n" \
  > /data/.neon/pageserver.toml && \
  chown -R neon:neon /data/.neon

# Create Railway scripts directly in the container
RUN set -e \
    && echo '#!/bin/bash\n\
set -e\n\
\n\
# Create necessary directories\n\
mkdir -p /data/.neon/safekeepers/sk1\n\
mkdir -p /data/.neon/pageserver\n\
\n\
# Create identity.toml\n\
echo "id=1234" > "/data/.neon/identity.toml"\n\
\n\
# Create pageserver.toml\n\
cat > /data/.neon/pageserver.toml << EOF\n\
broker_endpoint='"'"'http://storage_broker:50051'"'"'\n\
pg_distrib_dir='"'"'/usr/local/'"'"'\n\
listen_pg_addr='"'"'0.0.0.0:6400'"'"'\n\
listen_http_addr='"'"'0.0.0.0:9898'"'"'\n\
availability_zone='"'"'railway'"'"'\n\
EOF\n\
\n\
# Create safekeeper configuration\n\
cat > /data/.neon/safekeepers/sk1/config.toml << EOF\n\
id = 1\n\
pg_distrib_dir = '"'"'/usr/local/'"'"'\n\
listen_pg_addr = '"'"'0.0.0.0:5454'"'"'\n\
listen_http_addr = '"'"'0.0.0.0:7676'"'"'\n\
data_dir = '"'"'/data/.neon/safekeepers/sk1'"'"'\n\
broker_endpoint = '"'"'http://storage_broker:50051'"'"'\n\
EOF\n\
\n\
# Set permissions\n\
chmod -R 755 /data/.neon\n\
\n\
echo "Initialization complete!"\n'\
    > /usr/local/bin/railway-init.sh \
    && echo '#!/bin/bash\n\
set -e\n\
\n\
# Run the initialization script\n\
/usr/local/bin/railway-init.sh\n\
\n\
# Start the storage broker in the background\n\
storage_broker --listen-addr=0.0.0.0:50051 &\n\
STORAGE_BROKER_PID=$!\n\
echo "Storage broker started with PID $STORAGE_BROKER_PID"\n\
\n\
# Wait for the storage broker to start\n\
sleep 5\n\
\n\
# Start the safekeeper in the background\n\
safekeeper --listen-pg=0.0.0.0:5454 --listen-http='"'"'0.0.0.0:7676'"'"' --id=1 --broker-endpoint=http://localhost:50051 -D /data/.neon/safekeepers/sk1 &\n\
SAFEKEEPER_PID=$!\n\
echo "Safekeeper started with PID $SAFEKEEPER_PID"\n\
\n\
# Wait for the safekeeper to start\n\
sleep 5\n\
\n\
# Start the pageserver in the background\n\
echo "Starting pageserver..."\n\
pageserver -D /data/.neon &\n\
PAGESERVER_PID=$!\n\
echo "Pageserver started with PID $PAGESERVER_PID"\n\
\n\
# Wait for the pageserver to start\n\
sleep 5\n\
\n\
# Initialize tenant and create compute endpoint\n\
echo "Initializing tenant and compute endpoint..."\n\
/usr/local/bin/railway-init-tenant.sh\n\
\n\
# Keep the script running\n\
echo "All services started. Keeping container alive..."\n\
tail -f /dev/null\n'\
    > /usr/local/bin/railway-start.sh \
    && echo '#!/bin/bash\n\
set -e\n\
\n\
# Check if pageserver is running\n\
if ! curl -s http://localhost:9898/v1/status > /dev/null; then\n\
  echo "Pageserver is not running"\n\
  exit 1\n\
fi\n\
\n\
# Check if storage_broker is running\n\
if ! nc -z localhost 50051; then\n\
  echo "Storage broker is not running"\n\
  exit 1\n\
fi\n\
\n\
# Check if safekeeper is running\n\
if ! curl -s http://localhost:7676/v1/status > /dev/null; then\n\
  echo "Safekeeper is not running"\n\
  exit 1\n\
fi\n\
\n\
# All services are running\n\
echo "All services are running"\n\
exit 0\n'\
    > /usr/local/bin/railway-health-check.sh \
    && echo '#!/bin/bash\n\
set -e\n\
\n\
# Wait for the pageserver to be ready\n\
echo "Waiting for pageserver to be ready..."\n\
until curl -s http://localhost:9898/v1/status > /dev/null; do\n\
  sleep 1\n\
done\n\
echo "Pageserver is ready"\n\
\n\
# Initialize neon_local\n\
echo "Initializing neon_local..."\n\
neon_local init\n\
\n\
# Create a tenant\n\
echo "Creating tenant..."\n\
TENANT_ID=$(neon_local tenant create | grep "tenant" | awk '"'"'{print $2}'"'"')\n\
echo "Tenant created: $TENANT_ID"\n\
\n\
# Set the tenant as default\n\
echo "Setting tenant as default..."\n\
neon_local tenant set-default $TENANT_ID\n\
\n\
# Create a timeline\n\
echo "Creating timeline..."\n\
TIMELINE_ID=$(neon_local timeline create | grep "timeline" | awk '"'"'{print $2}'"'"')\n\
echo "Timeline created: $TIMELINE_ID"\n\
\n\
# Create an endpoint\n\
echo "Creating endpoint..."\n\
neon_local endpoint create main\n\
echo "Endpoint created"\n\
\n\
# Start the endpoint\n\
echo "Starting endpoint..."\n\
neon_local endpoint start main\n\
echo "Endpoint started"\n\
\n\
echo "Initialization complete!"\n'\
    > /usr/local/bin/railway-init-tenant.sh \
    && chmod +x /usr/local/bin/railway-*.sh

USER neon
EXPOSE 6400
EXPOSE 9898

CMD ["/usr/local/bin/pageserver", "-D", "/data/.neon"]
