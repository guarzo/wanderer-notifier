# Wanderer Notifier: Project Overview

## Project Purpose

Wanderer Notifier is a real-time notification system designed for EVE Online players that integrates with Discord to deliver timely alerts about in-game events. The application bridges the gap between EVE Online's game world and external communication platforms, ensuring players never miss critical events even when they're not actively monitoring the game.

The core purpose of Wanderer Notifier is to:

1. **Enhance Situational Awareness**: Provide immediate notifications about important in-game events
2. **Streamline Communication**: Deliver critical information directly to Discord channels where team members already collaborate
3. **Improve Response Time**: Enable faster reactions to game events through prompt notifications
4. **Centralize Intelligence**: Consolidate information about tracked systems and characters in one place

## Key Features

### 1. Real-Time Notifications

Wanderer Notifier delivers three primary types of alerts:

- **Kill Notifications**: When ships are destroyed in tracked systems or involving tracked characters
- **Character Tracking Notifications**: When new characters are added to the tracking list
- **System Notifications**: When new systems are discovered or added to the map

Each notification type is available in two formats:
- Rich embeds with detailed information (for licensed users)
- Basic text notifications with essential information (for free users)

### 2. Flexible Configuration

- **Environment-Based Setup**: Simple configuration through environment variables
- **Selective Notification Control**: Enable/disable specific notification types
- **Docker Deployment**: Easy deployment using Docker and Docker Compose
- **Web Dashboard**: Monitor system status and notification statistics

### 3. Integration Capabilities

- **Discord Integration**: Seamless delivery of notifications to Discord channels
- **Map API Integration**: Connection with Wanderer mapping system for system tracking
- **zKillboard Integration**: Enrichment of kill data with detailed information
- **ESI (EVE Swagger Interface) Integration**: Access to official EVE Online data

### 4. Reliability Features

- **Cache Management**: Efficient data caching to reduce API calls
- **Error Handling**: Robust error recovery mechanisms
- **Rate Limiting**: Intelligent handling of API rate limits
- **Notification Deduplication**: Prevention of duplicate notifications

## Technology Stack

### Backend

- **Elixir/Erlang**: Core programming language and runtime
- **Phoenix Framework**: Web framework for the dashboard
- **OTP (Open Telecom Platform)**: For building distributed, fault-tolerant applications

### Data Management

- **In-Memory Cache**: For efficient data storage and retrieval
- **File-Based Persistence**: For configuration and state management

### External Services

- **Discord API**: For sending notifications to Discord channels
- **zKillboard API**: For retrieving and enriching kill data
- **EVE ESI (Swagger Interface)**: For accessing official EVE Online data
- **Wanderer Map API**: For system tracking and discovery

### Deployment

- **Docker**: Containerization for consistent deployment
- **Docker Compose**: Multi-container orchestration
- **Environment Variables**: Configuration management

## User Workflows

### Initial Setup

1. **Download and Configure**:
   - Pull the Docker image
   - Create a `.env` file with Discord credentials and map API details
   - Configure optional notification settings

2. **Deploy**:
   - Run with Docker Compose
   - Verify successful startup via logs

3. **Validate**:
   - Check the web dashboard for system status
   - Test notifications using the test endpoint

### Daily Operation

1. **Monitor Notifications**:
   - Receive real-time alerts in Discord for kills, new characters, and new systems
   - View detailed information through rich embeds (licensed users)

2. **Dashboard Monitoring**:
   - Access the web dashboard to view system status
   - Monitor notification statistics and resource usage
   - Check license status and feature availability

3. **Configuration Adjustments**:
   - Enable/disable specific notification types as needed
   - Update tracking parameters without service restart

### Troubleshooting

1. **Check Status**:
   - View system status on the web dashboard
   - Examine logs for error messages

2. **Test Functionality**:
   - Use test endpoints to verify notification delivery
   - Validate Discord bot permissions

3. **Resolve Issues**:
   - Update configuration if needed
   - Restart the service for configuration changes
   - Check external service availability

## Licensing Model

Wanderer Notifier operates on a dual-tier model:

### Free Version
- Basic text notifications for all event types
- Unlimited system and character tracking
- Basic web dashboard
- 24-hour notification history

### Licensed Version
- Rich embed notifications with detailed information and images
- Unlimited system and character tracking
- Full web dashboard with detailed statistics
- 72-hour notification history

## Future Development

Planned enhancements for Wanderer Notifier include:

1. **Enhanced Notification Templates**: More customization options for notification appearance
2. **Advanced Filtering**: More granular control over which events trigger notifications
3. **Additional Integration Points**: Connection with more EVE Online data sources
4. **Expanded Dashboard**: More detailed analytics and visualization tools
5. **Mobile Notifications**: Push notifications for mobile devices

---

This project overview provides a comprehensive understanding of Wanderer Notifier, its purpose, features, and technical implementation. It serves as a reference for both technical team members working on the codebase and non-technical stakeholders interested in the application's capabilities. 