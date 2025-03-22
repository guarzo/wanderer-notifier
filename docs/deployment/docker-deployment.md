# Docker Deployment

This document outlines the process for deploying the WandererNotifier application using Docker.

## Prerequisites

Before deploying WandererNotifier, ensure you have:

1. Docker installed on your server
2. A valid WandererNotifier license key
3. A Discord bot token with appropriate permissions
4. Access to the required external APIs (Map API, etc.)

## Deployment Options

WandererNotifier supports two primary deployment methods:

1. **Docker** - Recommended for most deployments
2. **Manual** - For specific customization needs

## Docker Deployment

### Step 1: Pull the Docker Image

Pull the latest WandererNotifier image:

```bash
docker pull wanderernotifier/app:latest
```

### Step 2: Create an Environment File

Create a `.env` file with the following structure:

```
# Core configuration
DISCORD_BOT_TOKEN=your_discord_bot_token
LICENSE_KEY=your_license_key
DISCORD_CHANNEL_ID=your_discord_channel_id

# Map configuration
MAP_URL=your_map_url
MAP_NAME=your_map_name
MAP_TOKEN=your_map_token

# Feature enablement
ENABLE_NOTIFICATIONS=true
ENABLE_KILL_NOTIFICATIONS=true
ENABLE_SYSTEM_NOTIFICATIONS=true
ENABLE_CHARACTER_NOTIFICATIONS=true
```

### Step 3: Start the Container

Run the container with your environment file:

```bash
docker run -d \
  --name wanderer-notifier \
  --restart unless-stopped \
  --env-file .env \
  -p 127.0.0.1:4000:4000 \
  -p 127.0.0.1:3001:3001 \
  wanderernotifier/app:latest
```

### Step 4: Verify Deployment

Check that the service is running correctly:

```bash
docker ps
```

The container should show as "Up" and running.

### Docker Compose Alternative

If you prefer using Docker Compose, create a `docker-compose.yml` file:

```yaml
version: "3.8"

services:
  # Main application
  app:
    image: wanderernotifier/app:latest
    restart: unless-stopped
    env_file: .env
    ports:
      - "127.0.0.1:4000:4000"
      - "127.0.0.1:3001:3001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Then start it with:

```bash
docker-compose up -d
```

## Port Configuration

The application exposes two services with configurable ports:

- `PORT=4000` - Main application web interface and health endpoint
- `CHART_SERVICE_PORT=3001` - Chart generation service

Both port settings can be configured via environment variables. When mapping ports in Docker, make sure to map both services:

```bash
docker run -d \
  --name wanderer-notifier \
  --restart unless-stopped \
  --env-file .env \
  -p 127.0.0.1:4000:4000 \
  -p 127.0.0.1:3001:3001 \
  wanderernotifier/app:latest
```

If you change the default ports using environment variables, adjust your port mappings accordingly:

```bash
docker run -d \
  --name wanderer-notifier \
  --restart unless-stopped \
  -e PORT=8080 \
  -e CHART_SERVICE_PORT=8081 \
  --env-file .env \
  -p 127.0.0.1:8080:8080 \
  -p 127.0.0.1:8081:8081 \
  wanderernotifier/app:latest
```

For security, these ports are bound to localhost (127.0.0.1) and should be exposed through a reverse proxy for production use.

## Reverse Proxy Configuration

For production deployments, configure a reverse proxy (such as Nginx or Traefik) to:

1. Provide SSL/TLS termination
2. Handle proper HTTP headers
3. Implement access control if needed

Example Nginx configuration:

```nginx
server {
    listen 443 ssl;
    server_name wanderer-notifier.yourdomain.com;

    ssl_certificate /path/to/certificate.crt;
    ssl_certificate_key /path/to/private.key;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Container Resources

Recommended resource allocation:

- 1-2GB RAM
- 2 CPU cores

Adjust these values based on your specific workload and the number of systems/characters being tracked.

## Updating the Application

To update to a newer version:

1. Pull the latest image:

   ```bash
   docker pull wanderernotifier/app:latest
   ```

2. Restart the container:
   ```bash
   docker stop wanderer-notifier
   docker rm wanderer-notifier
   # Then run the container again as in Step 3
   ```

Or with Docker Compose:

```bash
docker-compose pull
docker-compose down
docker-compose up -d
```

## Monitoring

Monitor the application using:

1. Application health endpoint: `http://localhost:4000/health`
2. Docker container logs:
   ```bash
   docker logs -f wanderer-notifier
   ```

## Troubleshooting

Common issues and solutions:

### Discord Notification Issues

If Discord notifications aren't being sent:

1. Verify your bot token is correct
2. Check that the bot has the necessary permissions in your Discord server
3. Examine application logs for Discord API errors:
   ```bash
   docker logs wanderer-notifier | grep DISCORD
   ```

### Map API Connection Issues

If the application can't connect to the Map API:

1. Verify your Map API credentials are correct
2. Check for network connectivity issues
3. Look for error messages in logs:
   ```bash
   docker logs wanderer-notifier | grep "API TRACE"
   ```

## Production Considerations

For production deployments:

1. Use specific image tags rather than `latest` to ensure reproducible deployments
2. Set up external monitoring for service availability
3. Implement log rotation for container logs
4. Consider using Docker Swarm or Kubernetes for high-availability deployments

## Security Considerations

Enhance the security of your deployment by:

1. Restricting container network access to only required ports
2. Using Docker secrets or encrypted environment variables for sensitive data
3. Running containers with non-root users when possible
4. Regularly updating base images to address security vulnerabilities
5. Implementing proper firewall rules on the host
