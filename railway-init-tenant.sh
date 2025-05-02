#!/bin/bash
set -e

# Wait for the pageserver to be ready
echo "Waiting for pageserver to be ready..."
until curl -s http://localhost:9898/v1/status > /dev/null; do
  sleep 1
done
echo "Pageserver is ready"

# Initialize neon_local
echo "Initializing neon_local..."
neon_local init

# Create a tenant
echo "Creating tenant..."
TENANT_ID=$(neon_local tenant create | grep "tenant" | awk '{print $2}')
echo "Tenant created: $TENANT_ID"

# Set the tenant as default
echo "Setting tenant as default..."
neon_local tenant set-default $TENANT_ID

# Create a timeline
echo "Creating timeline..."
TIMELINE_ID=$(neon_local timeline create | grep "timeline" | awk '{print $2}')
echo "Timeline created: $TIMELINE_ID"

# Create an endpoint
echo "Creating endpoint..."
neon_local endpoint create main
echo "Endpoint created"

# Start the endpoint
echo "Starting endpoint..."
neon_local endpoint start main
echo "Endpoint started"

echo "Initialization complete!"
