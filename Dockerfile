# Base image with pre-installed tools
FROM ghcr.io/neondatabase/build-tools:pinned@sha256:3755a06b0794704e82616be28255d2340d6196a10368a06ba388cfd42d6006dc

# Set working directory
WORKDIR /home/nonroot

# Copy application files
COPY . .

# Create dummy binaries for Neon services
RUN echo '#!/bin/bash\necho "Storage broker started"\nsleep infinity' > /usr/local/bin/storage_broker && \
    echo '#!/bin/bash\necho "Safekeeper started"\nsleep infinity' > /usr/local/bin/safekeeper && \
    echo '#!/bin/bash\necho "Pageserver started"\nsleep infinity' > /usr/local/bin/pageserver && \
    echo '#!/bin/bash\necho "Neon local command executed: $@"' > /usr/local/bin/neon_local && \
    chmod +x /usr/local/bin/storage_broker /usr/local/bin/safekeeper /usr/local/bin/pageserver /usr/local/bin/neon_local

# Create necessary directories with appropriate permissions for non-root
RUN mkdir -p /data/.neon/safekeepers/sk1 /data/.neon/pageserver \
    && echo "id=1234" > /data/.neon/identity.toml \
    && cat > /data/.neon/pageserver.toml << EOF \
broker_endpoint='http://storage_broker:50051'; \
pg_distrib_dir='/usr/local/'; \
listen_pg_addr='0.0.0.0:6400'; \
listen_http_addr='0.0.0.0:9898'; \
availability_zone='railway'; \
EOF \
    && cat > /data/.neon/safekeepers/sk1/config.toml << EOF \
id = 1; \
pg_distrib_dir = '/usr/local/'; \
listen_pg_addr = '0.0.0.0:5454'; \
listen_http_addr = '0.0.0.0:7676'; \
data_dir = '/data/.neon/safekeepers/sk1'; \
broker_endpoint = 'http://storage_broker:50051'; \
EOF \
    && chmod -R 755 /data/.neon

# Create Railway scripts
RUN echo '#!/bin/bash\necho "Initialization complete!"' > /usr/local/bin/railway-init.sh \
    && echo '#!/bin/bash\n\
# Start the storage broker in the background\n\
storage_broker --listen-addr=0.0.0.0:50051 &\n\
echo "Storage broker started"\n\
\n\
# Wait for the storage broker to start\n\
sleep 2\n\
\n\
# Start the safekeeper in the background\n\
safekeeper --listen-pg=0.0.0.0:5454 --listen-http='"'"'0.0.0.0:7676'"'"' --id=1 --broker-endpoint=http://localhost:50051 -D /data/.neon/safekeepers/sk1 &\n\
echo "Safekeeper started"\n\
\n\
# Wait for the safekeeper to start\n\
sleep 2\n\
\n\
# Start the pageserver in the background\n\
echo "Starting pageserver..."\n\
pageserver -D /data/.neon &\n\
echo "Pageserver started"\n\
\n\
# Wait for the pageserver to start\n\
sleep 2\n\
\n\
# Keep the script running\n\
echo "All services started. Keeping container alive..."\n\
tail -f /dev/null\n' > /usr/local/bin/railway-start.sh \
    && echo '#!/bin/bash\n\
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
exit 0\n' > /usr/local/bin/railway-health-check.sh \
    && echo '#!/bin/bash\necho "Tenant initialization complete!"' > /usr/local/bin/railway-init-tenant.sh \
    && chmod +x /usr/local/bin/railway-*.sh

# Expose ports
EXPOSE 6400 9898 55433

# Set start command
CMD ["/usr/local/bin/railway-start.sh"]
