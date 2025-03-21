# Architecture Overview

This document provides a high-level overview of the WandererNotifier architecture and design principles.

## System Purpose

WandererNotifier is an application designed to monitor EVE Online game data and deliver notifications about important events to Discord channels. The system processes data from multiple sources, applies business rules to determine notification relevance, and delivers formatted notifications to configured channels.

## Architectural Style

WandererNotifier follows an **event-driven**, **functional**, and **component-based** architecture:

- **Event-driven**: The system responds to external events (killmails, character location changes, etc.) and scheduled events (TPS charts, system updates).
- **Functional**: Pure functions are preferred where possible, with side effects isolated to specific boundary modules.
- **Component-based**: The system is divided into distinct components with clear responsibilities and interfaces.

## High-Level Architecture Diagram

```
┌─────────────┐    ┌────────────┐           ┌─────────────┐
│             │    │            │           │             │
│  External   │    │ WandererNotifier       │  Discord    │
│  Data       ├────►            ├───────────► Channels    │
│  Sources    │    │ Application│           │             │
│             │    │            │           │             │
└─────────────┘    └────────────┘           └─────────────┘
```

## Core Design Principles

1. **Separation of Concerns**: Each component has a single responsibility.
2. **Immutable Data**: Data structures are immutable, with transformations creating new data rather than modifying existing data.
3. **Domain-Driven Design**: The codebase is organized around business concepts rather than technical details.
4. **Error Isolation**: Failures in one component should not cascade to other components.
5. **Observability**: The system provides logs, metrics, and health checks for monitoring.

## Key Subsystems

### 1. Data Acquisition

Responsible for obtaining data from external sources:

- WebSocket connections to zKillboard
- REST API calls to EVE ESI, Wanderer Map API, and Corp Tools
- Scheduled polling for data updates

### 2. Data Processing

Transforms and enriches raw data:

- Validation of incoming data
- Normalization into domain structures
- Enrichment with additional context
- Filtering of irrelevant data

### 3. Notification System

Determines when and what to notify:

- Applies business rules to determine notification triggers
- Formats notifications for target platforms
- Delivers notifications to configured channels
- Rate limits to prevent notification spam

### 4. Scheduling System

Manages time-based operations:

- Periodic chart generation
- Regular data updates
- Cleanup and maintenance tasks
- Health checks

### 5. Caching System

Provides efficient data access:

- Time-to-live (TTL) based caching
- Consistent interface for component access
- Cache invalidation strategies
- Memory management

## Technical Stack

### Backend

- **Language**: Elixir (BEAM VM)
- **Web Framework**: Phoenix (for health endpoints)
- **HTTP Client**: Tesla

### Infrastructure

- **Containerization**: Docker
- **Configuration**: Environment variables
- **Logging**: JSON structured logging

## Performance Considerations

WandererNotifier is designed to handle:

- Processing of high-volume real-time killmail data
- Multiple concurrent notifications
- Efficient caching to minimize external API calls
- Graceful handling of API rate limits
- Reliable delivery of notifications, even during partial system outages

## Security Architecture

- Sensitive credentials stored as environment variables
- API tokens never exposed in logs or error messages
- Fixed-function application with minimal attack surface
- Regular updates of dependencies to address security vulnerabilities

## Deployment Model

WandererNotifier is designed to be deployed as:

- A Docker container
- A single-instance application (not clustered)
- Environment-configurable for different deployments
