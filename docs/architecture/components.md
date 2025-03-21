# System Components

This document provides detailed information about the main components of the WandererNotifier system.

## Overview

WandererNotifier is composed of several key components that work together to provide a complete notification and visualization system. These components are organized in a modular architecture to ensure separation of concerns, maintainability, and scalability.

## Core Components

### 1. Core Configuration

The `WandererNotifier.Core.Config` module serves as the central configuration hub for the entire application. It provides:

- Environment variable management
- Feature flag system
- Centralized timing configuration
- License validation and feature restrictions

Key sub-modules include:

- `Features` - For feature flag management
- `Timings` - For centralized timing configuration
- `License` - For license validation and management

### 2. API Clients

API clients are specialized modules that interface with external APIs:

#### Map API Client

- **Purpose**: Retrieves data about solar systems, characters, and activity from the Wanderer Map API.
- **Key modules**:
  - `WandererNotifier.Api.Map.SystemsClient` - Handles system data
  - `WandererNotifier.Api.Map.CharactersClient` - Manages character data
  - `WandererNotifier.Api.Map.UrlBuilder` - Constructs API URLs
  - `WandererNotifier.Api.Map.ResponseValidator` - Validates API responses

#### ESI Client

- **Purpose**: Interfaces with EVE Online's Swagger Interface (ESI) to retrieve game data.
- **Key modules**:
  - `WandererNotifier.Api.Esi.Character` - Retrieves character information
  - `WandererNotifier.Api.Esi.Killmail` - Fetches killmail details
  - `WandererNotifier.Api.Esi.Universe` - Gets universe data (systems, regions, etc.)

#### zKillboard Client

- **Purpose**: Connects to zKillboard for real-time killmail data.
- **Key modules**:
  - `WandererNotifier.Api.ZKill.WebSocket` - Maintains WebSocket connection
  - `WandererNotifier.Api.ZKill.Rest` - Makes REST API calls for historical data

#### Corp Tools Client

- **Purpose**: Retrieves TPS (Tranquility Per Second) data and other specialized charts.
- **Key modules**:
  - `WandererNotifier.Api.CorpTools.Client` - Main interface for the API
  - `WandererNotifier.Api.CorpTools.TPSClient` - Specialized client for TPS data

### 3. Structured Data Types

The application uses domain-specific structs to represent data in a consistent format:

- `WandererNotifier.Data.Character` - Represents character data
- `WandererNotifier.Data.MapSystem` - Represents solar system data
- `WandererNotifier.Data.Killmail` - Represents killmail data

### 4. Cache Repository

The `WandererNotifier.Cache.Repository` provides a unified caching interface with:

- Consistent API for storing and retrieving data
- TTL-based expiration
- Conversion utilities for serialization
- In-memory storage for efficient access

### 5. Scheduler System

The scheduler system manages periodic tasks and is composed of:

- `WandererNotifier.Schedulers.Supervisor` - Supervises all schedulers
- `WandererNotifier.Schedulers.Registry` - Registers and manages scheduler instances
- `WandererNotifier.Schedulers.Factory` - Creates schedulers of appropriate types
- `WandererNotifier.Schedulers.BaseScheduler` - Base behavior for all schedulers

Specific scheduler implementations include:

- `TPS Chart Scheduler` - Generates and sends TPS charts
- `Activity Chart Scheduler` - Creates character activity charts
- `Character Update Scheduler` - Updates tracked character data
- `System Update Scheduler` - Updates tracked system data

### 6. Notification Services

Notification services manage the creation and delivery of notifications:

- `WandererNotifier.Discord.Service` - Sends notifications to Discord
- `WandererNotifier.Discord.Formatter` - Formats notifications for Discord
- `WandererNotifier.Services.NotificationDeterminer` - Determines what triggers notifications
- `WandererNotifier.Services.KillProcessor` - Processes killmail data for notifications

### 7. Chart Generation

Chart generation components create visual representations of data:

- `WandererNotifier.Charts.ChartConfig` - Provides standardized chart configuration
- `WandererNotifier.Charts.Generator` - Creates chart data structures
- `WandererNotifier.Charts.ExternalService` - Interfaces with external chart generation services
- `WandererNotifier.Charts.Formatter` - Formats chart data for Discord

## Component Interactions

### Kill Notification Flow

1. **WebSocket Connection** (`ZKill.WebSocket`) receives killmail data
2. **Message Processor** (`KillProcessor`) validates and processes the data
3. **Notification Determiner** checks if notification should be sent
4. **ESI Client** enriches killmail with additional data
5. **Formatter** creates a Discord embed
6. **Discord Service** sends the notification to the appropriate channel

### Scheduled Chart Flow

1. **Scheduler** (`TPSChartScheduler`) triggers at the scheduled time
2. **Corp Tools Client** fetches latest TPS data
3. **Chart Generator** converts data to chart configuration
4. **External Service** generates the chart image
5. **Discord Service** sends the chart to the configured channel

## Deployment Architecture

In a deployed environment, the application runs as a single Docker container with all components:

```
Docker Container
└── Elixir Application
    ├── Core Components
    ├── API Clients
    ├── Schedulers
    └── Services
```

## Future Component Plans

Planned improvements to the component architecture include:

1. Implementing additional structured data types:
   - `Corporation` - For corporation data
   - `Alliance` - For alliance data
   - `SolarSystem` - For ESI solar system data
   - `UniverseType` - For ship and item data
2. Enhancing component isolation:
   - Moving Killmail processing to dedicated GenServer
   - Implementing circuit breakers for API clients
3. Improving cache strategies:
   - Per-component cache repositories
   - Adaptive TTL based on data usage patterns
