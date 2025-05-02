#!/bin/bash
set -e

# Check if pageserver is running
if ! curl -s http://localhost:9898/v1/status > /dev/null; then
  echo "Pageserver is not running"
  exit 1
fi

# Check if storage_broker is running
if ! nc -z localhost 50051; then
  echo "Storage broker is not running"
  exit 1
fi

# Check if safekeeper is running
if ! curl -s http://localhost:7676/v1/status > /dev/null; then
  echo "Safekeeper is not running"
  exit 1
fi

# All services are running
echo "All services are running"
exit 0
