# Docker Deployment Guide

## Prerequisites

- Docker
- Docker Compose

## Configuration

1. Create a `.env` file in the project root:

```bash
# Discord Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_CHANNEL_ID=your_discord_channel_id

# Map Configuration
MAP_URL_WITH_NAME=your_map_url_with_name
MAP_TOKEN=your_map_token

# License Configuration
LICENSE_KEY=your_license_key
# BOT_API_TOKEN is not needed for production deployments (uses a constant value)
LICENSE_MANAGER_API_URL=https://license.manager.url  # Optional, defaults to production URL

# Application Configuration (optional)
PORT=4000          # Web server port, defaults to 4000
HOST=0.0.0.0       # Web server host, defaults to 0.0.0.0
```

## Deployment

1. Start the service:

```bash
# Pull and start the container in detached mode
docker-compose up -d
```

2. Check the logs:

```bash
# Follow the logs
docker-compose logs -f

# Show last 100 lines
docker-compose logs --tail=100
```

## Updating

To update to a new version:

```bash
# Pull the latest image
docker-compose pull

# Restart with new image
docker-compose up -d
```

## Monitoring

1. Check container status:
```bash
docker-compose ps
```

2. View logs:
```bash
docker-compose logs -f wanderer_notifier
```

3. Check container health:
```bash
docker inspect wanderer_notifier | grep Health
```

## Troubleshooting

1. Container won't start:
```bash
# Check logs
docker-compose logs wanderer_notifier

# Verify environment variables
docker-compose config
```

2. Application errors:
```bash
# Access container shell
docker-compose exec wanderer_notifier /bin/sh

# Check application status
bin/wanderer_notifier pid
bin/wanderer_notifier remote
```

3. Reset container:
```bash
docker-compose down
docker-compose up -d
```

## Backup

The application data is stored in a Docker volume. To backup:

```bash
# List volumes
docker volume ls

# Backup volume
docker run --rm -v wanderer_notifier_wanderer_data:/data -v $(pwd):/backup alpine tar czf /backup/wanderer_data.tar.gz /data
```

To restore:

```bash
# Restore volume
docker run --rm -v wanderer_notifier_wanderer_data:/data -v $(pwd):/backup alpine sh -c "cd /data && tar xzf /backup/wanderer_data.tar.gz --strip 1"
``` 