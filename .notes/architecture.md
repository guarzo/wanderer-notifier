# Wanderer Notifier: Architecture Document

## System Overview

Wanderer Notifier is built as a distributed, event-driven system that processes real-time data from EVE Online and delivers notifications to Discord. The architecture leverages Elixir/Erlang's OTP (Open Telecom Platform) to create a fault-tolerant, concurrent application capable of handling multiple notification streams simultaneously.

This document outlines the architectural design, component interactions, data flows, and key technical decisions that shape the Wanderer Notifier system.

## Architectural Principles

The architecture of Wanderer Notifier is guided by the following principles:

1. **Fault Tolerance**: The system must continue operating despite failures in individual components
2. **Concurrency**: Multiple operations should execute in parallel for optimal performance
3. **Loose Coupling**: Components should interact through well-defined interfaces
4. **Statelessness**: Core processing should be stateless where possible
5. **Idempotency**: Operations should be safely repeatable without side effects

## System Components

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                      Wanderer Notifier                           │
│                                                                  │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐    ┌──────────┐ │
│  │ Data      │    │ Processing│    │Notification│   │ Web      │ │
│  │ Collection│───▶│ Pipeline  │───▶│ Delivery  │   │ Dashboard │ │
│  │ Layer     │    │ Layer     │    │ Layer     │   │           │ │
│  └───────────┘    └───────────┘    └───────────┘   └──────────┘ │
│        ▲                                 │               ▲       │
└────────┼─────────────────────────────────┼───────────────┼───────┘
         │                                 │               │
         │                                 ▼               │
┌────────┼─────────────────────┐  ┌───────────────┐  ┌────┼────────┐
│ External Data Sources        │  │ Discord       │  │ User         │
│ - zKillboard API             │  │ - Channels    │  │ Interaction  │
│ - EVE ESI                    │  │ - Webhooks    │  │ - Browser    │
│ - Wanderer Map API           │  └───────────────┘  └──────────────┘
└──────────────────────────────┘
```

### 1. Data Collection Layer

The Data Collection Layer is responsible for gathering data from external sources and preparing it for processing.

#### Components:

- **ZKill Websocket Client**: Connects to zKillboard's websocket feed to receive real-time kill notifications
- **Map API Client**: Interfaces with the Wanderer Map API to track systems and characters
- **ESI Client**: Communicates with EVE Online's ESI API to enrich data with additional details
- **Backup Kills Processor**: Periodically polls for kills that might have been missed by the websocket

#### Key Characteristics:

- Implements retry mechanisms with exponential backoff
- Handles rate limiting for external APIs
- Maintains persistent connections where appropriate
- Buffers incoming data during processing bottlenecks

### 2. Processing Pipeline Layer

The Processing Pipeline Layer transforms raw data into structured notifications and applies business logic.

#### Components:

- **Kill Processor**: Enriches kill data and determines if notifications should be sent
- **Character Tracker**: Processes character data and detects new characters
- **System Tracker**: Monitors system data and identifies new systems
- **Enrichment Service**: Adds additional context to notifications (ship types, character details, etc.)

#### Key Characteristics:

- Implements filtering logic based on tracked systems and characters
- Performs deduplication to prevent multiple notifications for the same event
- Applies license-based feature restrictions
- Maintains processing statistics for monitoring

### 3. Notification Delivery Layer

The Notification Delivery Layer formats notifications and delivers them to Discord.

#### Components:

- **Discord Notifier**: Formats and sends notifications to Discord
- **Formatter**: Creates different notification formats based on license status
- **Rate Limiter**: Ensures Discord API rate limits are respected
- **Delivery Monitor**: Tracks successful and failed notification deliveries

#### Key Characteristics:

- Supports both rich embeds and plain text formats
- Handles Discord API errors gracefully
- Implements queuing for high-volume notification periods
- Provides delivery status feedback

### 4. Web Dashboard

The Web Dashboard provides a user interface for monitoring and configuration.

#### Components:

- **Web Server**: Handles HTTP requests and serves the dashboard
- **Status API**: Provides system status information
- **Configuration Interface**: Allows runtime configuration changes
- **Test Endpoints**: Facilitates testing of notification delivery

#### Key Characteristics:

- Lightweight, responsive interface
- Real-time status updates
- License status display
- Feature availability indicators

## Data Flows

### Kill Notification Flow

1. zKillboard websocket emits a kill event
2. ZKill Websocket Client receives the event and forwards it to the Kill Processor
3. Kill Processor checks if the kill involves a tracked system or character
4. If relevant, Kill Processor requests enrichment from the Enrichment Service
5. Enrichment Service fetches additional data from ESI if needed
6. Kill Processor formats the notification based on license status
7. Discord Notifier delivers the notification to the configured Discord channel

### Character Tracking Flow

1. Map API Client periodically polls for character updates
2. Character Tracker compares new data with cached data to identify new characters
3. For new characters, Character Tracker requests enrichment
4. Enrichment Service fetches character details from ESI
5. Character Tracker formats the notification based on license status
6. Discord Notifier delivers the notification to the configured Discord channel

### System Tracking Flow

1. Map API Client periodically polls for system updates
2. System Tracker compares new data with cached data to identify new systems
3. For new systems, System Tracker requests enrichment
4. Enrichment Service fetches system details from ESI if needed
5. System Tracker formats the notification based on license status
6. Discord Notifier delivers the notification to the configured Discord channel

## State Management

### Cache Repository

The Cache Repository is a central component for state management, providing:

- In-memory storage for frequently accessed data
- Persistence for critical state information
- Expiration policies for time-sensitive data
- Atomic operations for concurrent access

### Key Cached Data:

- Tracked systems and characters
- Recently processed kill IDs
- ESI lookup results
- API authentication tokens
- Rate limiting state

## Concurrency Model

Wanderer Notifier leverages Elixir/OTP's actor model for concurrency:

- Each major component runs as a separate GenServer process
- Supervision trees provide fault isolation and recovery
- Message passing enables loose coupling between components
- Process pools handle parallel processing of high-volume data

## Error Handling and Resilience

### Supervision Strategy

The application implements a multi-level supervision strategy:

```
                  ┌─────────────────┐
                  │ Application     │
                  │ Supervisor      │
                  └─────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
┌─────────────────┐ ┌─────────────┐ ┌─────────────┐
│ Data Collection │ │ Processing  │ │ Notification│
│ Supervisor      │ │ Supervisor  │ │ Supervisor  │
└─────────────────┘ └─────────────┘ └─────────────┘
          │               │               │
     ┌────┴────┐     ┌────┴────┐     ┌────┴────┐
     ▼         ▼     ▼         ▼     ▼         ▼
┌─────────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
│ ZKill   │ │ Map │ │ Kill│ │ ESI │ │ Disc│ │ Form│
│ Client  │ │ API │ │ Proc│ │ Cli │ │ Not │ │ atter│
└─────────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘
```

### Resilience Patterns

- **Circuit Breakers**: Prevent cascading failures when external services are unavailable
- **Retry with Backoff**: Automatically retry failed operations with exponential backoff
- **Fallback Mechanisms**: Provide alternative data sources when primary sources fail
- **Graceful Degradation**: Continue providing core functionality when non-critical components fail

## Scalability Considerations

### Current Scalability

The current architecture supports:

- Processing hundreds of kill notifications per minute
- Tracking thousands of systems and characters
- Serving dashboard requests from multiple users
- Maintaining connection to multiple external APIs

### Vertical Scaling

- Increase memory allocation for larger caches
- Add CPU cores for parallel processing
- Optimize database queries and caching strategies

### Horizontal Scaling Potential

Future versions could implement:

- Distributed processing across multiple nodes
- Load balancing for web dashboard requests
- Sharded caching for larger datasets
- Message queue integration for asynchronous processing

## Integration Points

### External APIs

1. **Discord API**
   - **Purpose**: Send notifications to Discord channels
   - **Integration Method**: REST API with bot token authentication
   - **Rate Limits**: 5 requests per second per channel
   - **Resilience**: Retry mechanism with backoff

2. **zKillboard API**
   - **Purpose**: Retrieve kill data and subscribe to real-time feeds
   - **Integration Method**: Websocket for real-time, REST API for historical data
   - **Rate Limits**: Varies based on endpoint
   - **Resilience**: Fallback to REST API if websocket fails

3. **EVE ESI (Swagger Interface)**
   - **Purpose**: Enrich data with official EVE Online information
   - **Integration Method**: REST API
   - **Rate Limits**: 20-100 requests per second depending on endpoint
   - **Resilience**: Extensive caching to minimize calls

4. **Wanderer Map API**
   - **Purpose**: Track systems and characters from the mapping system
   - **Integration Method**: REST API with token authentication
   - **Rate Limits**: Determined by service
   - **Resilience**: Polling with exponential backoff on failure

### Internal APIs

1. **Status API**
   - **Purpose**: Provide system status for the dashboard
   - **Endpoints**: `/api/status`, `/api/test-notification`
   - **Authentication**: None (internal use only)

2. **Configuration API**
   - **Purpose**: Allow runtime configuration changes
   - **Endpoints**: Various configuration endpoints
   - **Authentication**: None (internal use only)

## Security Considerations

### Authentication

- Discord bot token for Discord API access
- Map API token for Wanderer Map API access
- No authentication for internal dashboard (intended for local access only)

### Data Protection

- Sensitive configuration stored in environment variables
- No persistent storage of sensitive game data
- Minimal logging of sensitive information

### Network Security

- HTTPS for all external API communications
- Internal components communicate via process messages
- No direct exposure of internal APIs to the internet

## Key Technical Challenges

### 1. Real-Time Data Processing

**Challenge**: Processing high-volume, real-time kill data from zKillboard websocket.

**Solution**: 
- Implemented efficient websocket client with backpressure handling
- Used GenStage for data flow management
- Applied filtering early in the pipeline to reduce processing load

### 2. External API Reliability

**Challenge**: Dealing with occasional downtime or rate limiting from external APIs.

**Solution**:
- Implemented comprehensive retry mechanisms with exponential backoff
- Created fallback data sources where possible
- Developed extensive caching to reduce API dependency

### 3. Notification Deduplication

**Challenge**: Preventing duplicate notifications for the same event.

**Solution**:
- Maintained processed event registry with TTL
- Implemented idempotent processing
- Created unique identifiers for events across different data sources

### 4. License Feature Management

**Challenge**: Dynamically enabling/disabling features based on license status.

**Solution**:
- Centralized feature flag system
- License validation service with caching
- Feature-based code paths for different license tiers

## Deployment Architecture

### Docker-Based Deployment

```
┌─────────────────────────────────────────┐
│ Docker Host                             │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Wanderer Notifier Container     │    │
│  │                                 │    │
│  │  ┌─────────────┐ ┌───────────┐ │    │
│  │  │ Application │ │ Web Server│ │    │
│  │  └─────────────┘ └───────────┘ │    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
```

### Configuration Management

- Environment variables for all configuration
- Docker Compose for orchestration
- Volume mounting for persistent data (if needed)

## Performance Considerations

### Optimization Points

1. **Memory Usage**
   - Tuned cache sizes based on expected data volume
   - Implemented efficient data structures for frequent operations
   - Applied garbage collection strategies for temporary data

2. **CPU Utilization**
   - Distributed processing across multiple OTP processes
   - Optimized hot code paths for frequent operations
   - Implemented batching for high-volume operations

3. **Network Efficiency**
   - Minimized API calls through strategic caching
   - Implemented connection pooling for external services
   - Used binary protocols where available

## Monitoring and Observability

### Current Monitoring

- Basic statistics tracking (notifications sent, systems tracked, etc.)
- Web dashboard for system status
- Application logs for debugging

### Future Observability Enhancements

- Prometheus metrics integration
- Distributed tracing for request flows
- Enhanced logging with structured data
- Real-time alerting for system issues

## Conclusion

The Wanderer Notifier architecture is designed to provide reliable, real-time notifications for EVE Online events. Its Elixir/OTP foundation enables fault tolerance and concurrency, while the modular design allows for future expansion and enhancement.

The system balances performance with reliability, implementing robust error handling and resilience patterns to ensure consistent operation even when external services experience issues. The architecture supports the current feature set while providing a foundation for future scalability and feature additions.

---

*This architecture document serves as a high-level overview of the Wanderer Notifier system. Developers should refer to the codebase and specific module documentation for implementation details.* 