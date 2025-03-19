%{
  title: "Get Real-Time Notifications with Wanderer Notifier",
  author: "Wanderer Team",
  cover_image_uri: "/images/news/03-10-bots/bot.svg",
  tags: ~w(notifier discord notifications docker user-guide),
  description: "Download and run Wanderer Notifier to receive real-time notifications in your Discord channel. Learn how to get started with our Docker image and discover the different alerts you'll receive."
}

---

# Get Real-Time Notifications with Wanderer Notifier

Wanderer Notifier delivers real-time alerts directly to your Discord channel, so you never miss critical in-game events. Whether it's a significant kill event, a new tracked character, or a newly discovered system, our notifier keeps you informed with rich, detailed notifications.

## How to Get Started

### 1. Download the Docker Image

Pull the latest Wanderer Notifier image by running:

```bash
docker pull guarzo/wanderer-notifier:latest
```

### 2. Configure Your Environment

Create a `.env` file in your working directory with the following content. Replace the placeholder values with your actual credentials and settings:

```dotenv
# Required Configuration
DISCORD_BOT_TOKEN=your_discord_bot_token
DISCORD_CHANNEL_ID=your_discord_channel_id
MAP_URL_WITH_NAME="https://wanderer.ltd/<yourmap>"
MAP_TOKEN=your_map_api_token

# License Configuration (for enhanced features)
LICENSE_KEY=your_license_key

# Environment Configuration
MIX_ENV=prod

# Web Server Configuration (defaults shown)
PORT=4000
HOST=0.0.0.0

# Notification Control (all enabled by default)
# ENABLE_KILL_NOTIFICATIONS=true
# ENABLE_CHARACTER_TRACKING=true
# ENABLE_CHARACTER_NOTIFICATIONS=true
# ENABLE_SYSTEM_NOTIFICATIONS=true
```

### 3. Run Using Docker Compose

Create a `docker-compose.yml` file with the configuration below:

```yaml
services:
  wanderer_notifier:
    image: guarzo/wanderer-notifier:latest
    container_name: wanderer_notifier
    restart: unless-stopped
    environment:
      # Environment setting
      - MIX_ENV=prod
      
      # Discord Configuration
      - DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
      - DISCORD_CHANNEL_ID=${DISCORD_CHANNEL_ID}
      
      # Map Configuration
      - MAP_URL_WITH_NAME=${MAP_URL_WITH_NAME}
      - MAP_TOKEN=${MAP_TOKEN}
      
      # License Configuration
      - LICENSE_KEY=${LICENSE_KEY}
      - LICENSE_MANAGER_API_URL=${LICENSE_MANAGER_API_URL}
      
      # Application Configuration
      - PORT=${PORT:-4000}
      - HOST=${HOST:-0.0.0.0}
    ports:
      - "${PORT:-4000}:${PORT:-4000}"
    volumes:
      - wanderer_data:/app/data
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "${PORT:-4000}"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 10s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  wanderer_data:
```

Start the service by executing:

```bash
docker-compose up -d
```

Your notifier is now up and running—delivering alerts to your Discord channel automatically!

---

## Notification Types

Wanderer Notifier provides three main types of notifications, each with different presentation based on your license status:

### Kill Notifications

When a kill occurs in a tracked system or involves a tracked character:

- **With License**: Rich embed format with:
  - Ship thumbnail image
  - Detailed information about victim and attacker
  - Links to zKillboard profiles
  - Ship type details
  - ISK value of the kill
  - Corporation logos

![Licensed Kill Notification Example](/images/news/03-10-bots/paid-kill.png)

- **Without License**: Basic text notification with essential information:
  - System name
  - Victim name
  - Ship type lost

![Free Kill Notification Example](/images/news/03-10-bots/free-kill.png)

### Character Tracking Notifications

When a new character is added to your tracked list:

- **With License**: Rich embed with:
  - Character portrait
  - Corporation details
  - Direct link to zKillboard profile
  - Formatted timestamp

![Licensed Character Notification Example](/images/news/03-10-bots/paid-character.png)

- **Without License**: Simple text notification with character name

![Free Character Notification Example](/images/news/03-10-bots/free-character.png)

### System Notifications

When a new system is discovered or added to your map:

- **With License**: Rich embed with:
  - System name (including any aliases/temporary names)
  - Link to zKillboard for the system
  - Formatted timestamp

![Licensed System Notification Example](/images/news/03-10-bots/paid-system.png)

- **Without License**: Basic text notification with system name

![Free System Notification Example](/images/news/03-10-bots/free-system.png)

---

## License Features & Limitations

Wanderer Notifier now offers more functionality in the free version while still providing enhanced features with a valid license.

### Free Version Features

- **All Core Notifications**: Track systems and characters with basic notifications
- **Basic Web Dashboard**: View system status and license information
- **Unlimited Tracking**: No limits on the number of systems and characters you can track
- **Notification History**: 24-hour notification history retention

### Licensed Version Enhancements

- **Rich Notifications**: Visually appealing embeds with images, links, and detailed information
- **Extended History**: 72-hour notification history retention
- **Full Web Dashboard**: Access to detailed statistics and visualization tools

### Feature Comparison

| Feature | Free Version | Licensed Version |
|---------|-------------|-----------------|
| System Tracking | Unlimited | Unlimited |
| Character Tracking | Unlimited | Unlimited |
| Notification Format | Basic Text | Rich Embeds |
| Notification History | 24 hours | 72 hours |


---

## Web Dashboard

Wanderer Notifier includes a web dashboard that provides insights into your notification system:

1. Access the dashboard at `http://your-server-ip:8080`
2. View system status, license information, and notification statistics
3. Monitor resource usage and feature availability

The dashboard automatically refreshes every 30 seconds to provide up-to-date information. Licensed users gain access to additional dashboard features including detailed statistics and visualization tools.

---

## Configuration Options

Wanderer Notifier offers several configuration options to customize your notification experience:

### Notification Control

You can enable or disable specific notification types using these environment variables:

- **ENABLE_KILL_NOTIFICATIONS**: Enable/disable kill notifications (default: true)
- **ENABLE_CHARACTER_TRACKING**: Enable/disable the tracking of characters (default: true)
- **ENABLE_CHARACTER_NOTIFICATIONS**: Enable/disable notifications when new characters are added (default: true)
- **ENABLE_SYSTEM_NOTIFICATIONS**: Enable/disable notifications when new systems are added (default: true)

The difference between character tracking and character notifications:
- **Character Tracking**: Controls whether the application monitors characters at all
- **Character Notifications**: Controls whether you receive Discord alerts when new characters are added to tracking

To disable any notification type, set the corresponding variable to `false` or `0` in your `.env` file:

```dotenv
# Example: Disable kill notifications but keep character and system notifications
ENABLE_KILL_NOTIFICATIONS=false
```

These settings can be changed without restarting the application by updating your environment variables and reloading the configuration.

---

## Conclusion

Wanderer Notifier is designed to keep you informed of crucial in-game events with minimal hassle. The free version now provides unlimited tracking capabilities with basic notifications, while the licensed version enhances your experience with rich, detailed notifications and additional features.

By downloading the Docker image, setting up your environment via a simple `.env` file, and running the service with Docker Compose, you'll receive timely notifications in your Discord channel—letting you focus on what matters most in your gameplay.

For further support or questions, please contact the Wanderer Team.

Stay vigilant and enjoy your real-time alerts! 