# Deploying Neon on Railway

This guide provides instructions for deploying Neon, a serverless PostgreSQL alternative, on Railway.

## Prerequisites

- A Railway account
- Railway CLI installed locally (optional, for command-line deployment)

## Deployment Steps

### Option 1: Deploy via Railway Dashboard

1. Fork this repository to your GitHub account
2. Log in to your Railway account
3. Click "New Project" and select "Deploy from GitHub repo"
4. Select your forked Neon repository
5. Railway will automatically detect the `railway.toml` configuration and start the deployment
6. Once deployed, you can access your Neon instance using the provided URLs

### Option 2: Deploy via Railway CLI

1. Install the Railway CLI:
   ```
   npm i -g @railway/cli
   ```

2. Login to your Railway account:
   ```
   railway login
   ```

3. Initialize a new project:
   ```
   railway init
   ```

4. Deploy the project:
   ```
   railway up
   ```

## Configuration

The deployment is configured in the `railway.toml` file, which defines the following services:

- **pageserver**: The storage backend for compute nodes (port 9898)
- **storage_broker**: Service for storage coordination (port 50051)
- **safekeeper1**: Part of the redundant WAL service (port 7676)
- **compute**: PostgreSQL compute node (port 55433)

### Scripts

The deployment includes several scripts to automate the setup and management of Neon on Railway:

- **railway-init.sh**: Initializes the necessary directories and configuration files
- **railway-start.sh**: Starts all the required services (storage_broker, safekeeper, pageserver)
- **railway-init-tenant.sh**: Creates a tenant, timeline, and compute endpoint
- **railway-health-check.sh**: Checks if all services are running correctly

## Connecting to Your Neon Instance

Once deployed, you can connect to your Neon PostgreSQL instance using:

```
psql -h <railway-provided-host> -p 55433 -U cloud_admin postgres
```

Replace `<railway-provided-host>` with the actual host provided by Railway after deployment.

## Environment Variables

You can configure the following environment variables in the Railway dashboard:

- `RUST_LOG`: Log level (default: info)

## Persistent Storage

The deployment uses a persistent volume mounted at `/data` to store your database files.

## Troubleshooting

If you encounter any issues during deployment:

1. Check the Railway logs for error messages
2. Ensure all required ports are properly exposed
3. Verify that the persistent volume is correctly mounted

For more information about Neon, refer to the main [README.md](README.md) file.
