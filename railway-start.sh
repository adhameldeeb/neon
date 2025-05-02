#!/bin/bash
set -e

# Run the initialization script
./railway-init.sh

# Start the storage broker in the background
storage_broker --listen-addr=0.0.0.0:50051 &
STORAGE_BROKER_PID=$!
echo "Storage broker started with PID $STORAGE_BROKER_PID"

# Wait for the storage broker to start
sleep 5

# Start the safekeeper in the background
safekeeper --listen-pg=0.0.0.0:5454 --listen-http='0.0.0.0:7676' --id=1 --broker-endpoint=http://localhost:50051 -D /data/.neon/safekeepers/sk1 &
SAFEKEEPER_PID=$!
echo "Safekeeper started with PID $SAFEKEEPER_PID"

# Wait for the safekeeper to start
sleep 5

# Start the pageserver in the background
echo "Starting pageserver..."
pageserver -D /data/.neon &
PAGESERVER_PID=$!
echo "Pageserver started with PID $PAGESERVER_PID"

# Wait for the pageserver to start
sleep 5

# Initialize tenant and create compute endpoint
echo "Initializing tenant and compute endpoint..."
./railway-init-tenant.sh

# Keep the script running
echo "All services started. Keeping container alive..."
tail -f /dev/null
