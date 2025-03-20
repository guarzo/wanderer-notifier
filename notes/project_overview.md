# WandererNotifier Project Overview

## Purpose

WandererNotifier is a comprehensive notification and visualization system for EVE Online. It aggregates data from external APIs (ESI, Map API, zKillboard), processes game events, and delivers notifications (e.g., killmails, character activity) via Discord and a dedicated web dashboard with a focus on real-time monitoring and data visualization.

## Key Features

- **Real-Time Notifications:**  
  - Monitors ESI killmails, zKillboard feeds, character information, and system data
  - Sends timely alerts to configurable Discord channels with rich formatting
  - Supports different notification types with targeted delivery

- **Data Visualization:**  
  - Generates charts via a dedicated Node.js service with fallback strategies
  - Provides activity, system status, and TPS (Tranquility Per Second) charts
  - Delivers interactive React-based dashboard for viewing statistics and notifications

- **Robust API Integration:**  
  - Interfaces with multiple external APIs using specialized clients with structured data types
  - Implements validation, error handling, and retry mechanisms
  - Enforces structured data flow with domain-specific types

- **Modular Architecture:**
  - Core configuration system with feature flags
  - Comprehensive scheduler framework for periodic tasks
  - Factory pattern for notifiers with behavior-based interfaces
  - Adapter pattern for chart generation services

- **Scalability & Containerization:**  
  - Deployable via Docker with environment-specific configurations
  - Automated CI/CD pipelines using GitHub Actions
  - Focused on OTP principles for resilience and fault tolerance

## Technology Stack

- **Backend:**  
  - Elixir with OTP principles, GenServer-based schedulers, and structured logging
  - Behavior-driven design with factory patterns and adapters
  - Registry-based process tracking for improved management

- **Chart Service:**  
  - Node.js with Chart.js for server-side image generation
  - RESTful API with standardized response formats
  - File-based storage with automatic cleanup and monitoring

- **Frontend:**  
  - React built with Vite and styled with Tailwind CSS
  - Component-based architecture for different visualization types
  - Dashboard with debugging capabilities

- **Infrastructure:**  
  - Docker, GitHub Actions, and environment-based configuration
  - Health monitoring for services and resource usage

## Data Flow

1. **Collection:** External API clients fetch and validate game data
2. **Transformation:** Raw data is converted to structured domain types
3. **Storage:** Data is cached with appropriate TTLs
4. **Processing:** Business logic determines notification requirements
5. **Visualization:** Chart service generates visual representations
6. **Delivery:** Notifications are formatted and delivered to Discord
7. **Presentation:** Dashboard displays historical data and system status

## Target Audience

- **EVE Online Community:**  
  - Players and corporations seeking real-time game event notifications
  - Fleet commanders requiring system activity monitoring
  - Scouts tracking character movements and system changes

- **Developers & System Administrators:**  
  - Interested in a robust, modular notification system with modern tooling
  - Learning about Elixir/OTP architecture and design patterns

- **Data Visualization Enthusiasts:**  
  - Users who want to see complex game data transformed into actionable insights

## Current Development Focus

- **Chart Service Migration:**
  - Moving from external QuickChart.io to internal Node.js chart service
  - Implementing adapter pattern with fallback strategies
  - Enhancing chart generation capabilities and reliability

- **API Client Refactoring:**
  - Implementing structured data types for all API responses
  - Standardizing URL builders and response validators
  - Improving error handling and caching consistency

- **Scheduler Framework:**
  - Enhancing the comprehensive scheduler system
  - Improving monitoring and management capabilities
  - Standardizing timing configuration

## Roadmap & Future Directions

- **Feature Enhancements:**  
  - Extend notifications to additional platforms beyond Discord
  - Implement more granular user settings and filtering options
  - Add support for additional EVE Online data sources

- **Architecture Improvements:**  
  - Complete the structured data type implementation for all APIs
  - Enhance caching strategies with data-specific policies
  - Improve test coverage across all components

- **UI/UX Refinements:**  
  - Enhance dashboard with more interactive visualizations
  - Add user customization options for charts and notifications
  - Implement real-time updates in the web interface