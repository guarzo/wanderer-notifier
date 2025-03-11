# Wanderer Notifier Project Overview

<!-- 
ASSISTANT INSTRUCTIONS:
1. READ THIS DOCUMENT: At the start of any new conversation or user interaction, read this entire document to understand the project context.
2. MAINTAIN ACCURACY: Update this document when:
   - New features or components are added
   - Existing functionality is modified
   - Architecture changes are made
   - New notification types are implemented
3. VERSIONING: When updating this document, increment the version number and add a changelog entry
4. CONSISTENCY: Ensure all responses align with the architecture and functionality described here

Current Version: 1.0.0
Last Updated: 2024-03-20
Changelog:
- 1.0.0: Initial documentation of system architecture and components
-->

# Wanderer Notifier Project Overview

## System Architecture

Wanderer Notifier is an Elixir-based monitoring system for EVE Online kill events, built to provide real-time notifications through Discord. The system consists of several key components working together to process and filter kill events.

### Core Components

1. **Main Service (`Wanderer.Service`)**
   - Coordinates all system activities
   - Manages WebSocket connections to zKillboard
   - Handles periodic maintenance tasks
   - Maintains state of processed kills

2. **Kill Processor (`Wanderer.Service.KillProcessor`)**
   - Processes incoming kill messages
   - Filters kills based on tracked systems and characters
   - Coordinates kill enrichment and notification dispatch

3. **Discord Notifier (`Wanderer.Discord.Notifier`)**
   - Handles all Discord communication
   - Supports multiple notification types
   - Formats messages with rich embeds

4. **Map Systems Manager (`Wanderer.Map.Systems`)**
   - Manages tracked wormhole systems
   - Updates system data periodically
   - Notifies about new system discoveries

5. **Character Tracking (`Wanderer.Map.Characters`)**
   - Manages tracked character information
   - Updates character data
   - Notifies about new tracked characters

### Notification Types

1. **Kill Notifications**
   - Primary feature of the system
   - Triggered by ship destructions in EVE Online
   - Filtered by tracked systems and characters
   - Contains:
     - System location
     - Victim details (character, corp, ship)
     - Attacker details (final blow, top damage)
     - Kill value
     - Visual elements (ship thumbnail, corp icons)

2. **System Notifications**
   - Announces newly tracked systems
   - Includes system identification and links
   - Uses distinct orange color scheme

3. **Character Notifications**
   - Announces newly tracked characters
   - Includes character details and affiliations
   - Uses green color scheme

4. **Service Status Notifications**
   - System startup notifications
   - Connection status updates
   - Error reporting

### Data Flow

1. **Kill Event Detection**
   - Real-time WebSocket connection to zKillboard
   - Backup kill processing for missed events

2. **Data Enrichment**
   - ESI lookups for detailed information
   - Character and corporation resolution
   - Ship type identification

3. **Filtering Logic**
   - System-based filtering (tracked wormholes)
   - Character-based filtering (tracked pilots)
   - Deduplication through caching

4. **Notification Dispatch**
   - Discord webhook integration
   - Rich embed formatting
   - Error handling and retry logic

### Key Features

1. **Real-Time Processing**
   - WebSocket-based live monitoring
   - Immediate notification dispatch
   - Backup processing for reliability

2. **Smart Filtering**
   - Configurable system tracking
   - Character-based monitoring
   - Efficient caching

3. **Rich Information**
   - Detailed kill information
   - Visual elements (thumbnails, icons)
   - Formatted value presentation

4. **Reliability**
   - Error handling and recovery
   - Connection management
   - Cache-based deduplication

### Configuration

The system is configured through environment variables:
- Discord integration settings
- Map API configuration
- ESI and zKillboard endpoints
- Character tracking lists

This overview serves as a reference for understanding the system's architecture, components, and functionality. 