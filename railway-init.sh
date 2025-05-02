#!/bin/bash
set -e

# Create necessary directories
mkdir -p /data/.neon/safekeepers/sk1
mkdir -p /data/.neon/pageserver

# Create identity.toml
echo "id=1234" > "/data/.neon/identity.toml"

# Create pageserver.toml
cat > /data/.neon/pageserver.toml << EOF
broker_endpoint='http://storage_broker:50051'
pg_distrib_dir='/usr/local/'
listen_pg_addr='0.0.0.0:6400'
listen_http_addr='0.0.0.0:9898'
availability_zone='railway'
EOF

# Create safekeeper configuration
cat > /data/.neon/safekeepers/sk1/config.toml << EOF
id = 1
pg_distrib_dir = '/usr/local/'
listen_pg_addr = '0.0.0.0:5454'
listen_http_addr = '0.0.0.0:7676'
data_dir = '/data/.neon/safekeepers/sk1'
broker_endpoint = 'http://storage_broker:50051'
EOF

# Set permissions
chmod -R 755 /data/.neon

echo "Initialization complete!"
