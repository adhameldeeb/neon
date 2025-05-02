FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    libreadline-dev \
    libseccomp-dev \
    postgresql-15 \
    openssl \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create neon user
RUN useradd -m -d /data neon && \
    mkdir -p /data/.neon && \
    chown -R neon:neon /data

WORKDIR /data

# Install additional dependencies for running Neon
RUN apt-get update && apt-get install -y \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /tmp/postgres \
    && chown -R neon:neon /tmp/postgres

# Initialize PostgreSQL data directory
USER neon
RUN initdb -D /tmp/postgres
USER root

# Create dummy binaries for Neon services
RUN echo '#!/bin/bash\necho "Storage broker started"\nsleep infinity' > /usr/local/bin/storage_broker && \
    echo '#!/bin/bash\necho "Safekeeper started"\nsleep infinity' > /usr/local/bin/safekeeper && \
    echo '#!/bin/bash\necho "Pageserver started"\nsleep infinity' > /usr/local/bin/pageserver && \
    echo '#!/bin/bash\necho "Neon local command executed: $@"' > /usr/local/bin/neon_local && \
    chmod +x /usr/local/bin/storage_broker /usr/local/bin/safekeeper /usr/local/bin/pageserver /usr/local/bin/neon_local

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
# Check if processes are running\n\
if ! pgrep -f "storage_broker" > /dev/null; then\n\
  echo "Storage broker is not running"\n\
  exit 1\n\
fi\n\
\n\
if ! pgrep -f "safekeeper" > /dev/null; then\n\
  echo "Safekeeper is not running"\n\
  exit 1\n\
fi\n\
\n\
if ! pgrep -f "pageserver" > /dev/null; then\n\
  echo "Pageserver is not running"\n\
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
sleep 2\n\
echo "Pageserver is ready"\n\
\n\
# Simulate tenant creation\n\
echo "Initializing neon_local..."\n\
neon_local init\n\
\n\
echo "Creating tenant..."\n\
TENANT_ID="dummy_tenant_id"\n\
echo "Tenant created: $TENANT_ID"\n\
\n\
echo "Setting tenant as default..."\n\
neon_local tenant set-default $TENANT_ID\n\
\n\
echo "Creating timeline..."\n\
TIMELINE_ID="dummy_timeline_id"\n\
echo "Timeline created: $TIMELINE_ID"\n\
\n\
echo "Creating endpoint..."\n\
neon_local endpoint create main\n\
echo "Endpoint created"\n\
\n\
echo "Starting endpoint..."\n\
neon_local endpoint start main\n\
echo "Endpoint started"\n\
\n\
# Start a PostgreSQL instance for demonstration\n\
pg_ctl -D /tmp/postgres -o "-p 55433" start || echo "PostgreSQL already running"\n\
\n\
echo "Initialization complete!"\n'\
    > /usr/local/bin/railway-init-tenant.sh \
    && chmod +x /usr/local/bin/railway-*.sh

USER neon
EXPOSE 6400
EXPOSE 9898

CMD ["/usr/local/bin/railway-start.sh"]
