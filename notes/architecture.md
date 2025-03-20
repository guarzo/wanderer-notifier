# WandererNotifier Architecture Document

## Overview

The **WandererNotifier** system is designed to aggregate and process data from external game APIs (e.g., EVE Online's ESI, Map API, zKillboard) and deliver notifications (primarily to Discord) along with data visualization (via charts). The architecture emphasizes modularity, robust error handling, and scalability through clear separation of concerns with a focus on idiomatic Elixir practices and OTP principles.

## Components

### 1. Elixir Backend
- **Core Functions:**  
  - **Core Module:** Centralized configuration management in `Core.Config` with feature flags and environment variables handling
  - **API Clients:** Specialized modules under `lib/wanderer_notifier/api/` interface with external APIs:
    - **Map API:** Structured clients with URL builders and response validators
    - **ESI:** EVE Swagger Interface for game data
    - **zKillboard:** Real-time killmail data via WebSocket and REST API
    - **Corp Tools:** For TPS and other specific data
  - **Data Processing:** Implements business logic with structured data types for transformation, validation, and caching
  - **Schedulers Framework:** Comprehensive system of interval and time-based schedulers following OTP principles
- **Error Handling & Logging:**  
  - Centralized error handling with consistent patterns across modules
  - Structured validation and clear contracts instead of defensive programming
- **Configuration:**  
  - Environment-specific configurations in the `config/` directory
  - Feature flags system for selective feature enabling
  - Centralized timing configuration in `Core.Config.Timings`

### 2. Node.js Chart Service
- **Purpose:**  
  - Generates visual charts using Chart.js (configured for Discord's dark theme)
  - Provides endpoints for generating, saving, and returning chart images
- **Integration:**  
  - Invoked by the Elixir backend through adapter pattern with fallback strategies
  - Supports multiple chart types (TPS, Activity, etc.)
- **Deployment:**  
  - Runs in its own container; integrated into CI/CD pipelines
  - Includes health metrics and automatic cleanup of generated files

### 3. React Frontend (Dashboard)
- **Purpose:**  
  - Offers a dashboard for viewing notifications, charts, and other system data
- **Structure:**  
  - Located in the `renderer/` directory with components for various data visualizations
  - Specialized components for different chart types and data displays
- **Build & Deployment:**  
  - Built with modern tooling (Vite, Tailwind CSS) and deployed as part of the overall system

### 4. External Integrations & Infrastructure
- **External APIs:**  
  - **ESI:** For killmail and character data from EVE Online
  - **Map API:** For system and activity data with structured response handling
  - **zKillboard:** For real-time kill tracking
  - **Corp Tools API:** For TPS data and specialized charts
  - **Discord:** For notifications and interactive chart delivery
- **Containerization & CI/CD:**  
  - Dockerfiles, GitHub workflows, and deployment scripts ensure repeatable builds and streamlined deployments

## Data Flow & Communication

1. **Data Acquisition:**  
   - API clients fetch data from external sources using dedicated modules with URL builders
   - Response validators ensure data integrity through type checking and schema validation
2. **Transformation & Structures:**
   - Raw API data is converted to domain-specific structs (Character, MapSystem, KillMail, etc.)
   - Validation ensures data meets business requirements before processing
3. **Processing & Caching:**  
   - Validated data is transformed, cached with appropriate TTLs, and prepared for notifications
   - Cache repository provides consistent access patterns across all data types
4. **Chart Generation:**  
   - Chart configurations are created with standardized `ChartConfig` structs
   - Chart adapters process these configurations through the Node.js chart service
   - Fallback strategies ensure resilience in case of service failures
5. **Notification Delivery:**  
   - Factory pattern creates appropriate notifiers based on configuration
   - Final outputs (charts, alerts, status updates) are pushed to Discord or rendered in the dashboard
   - Direct file attachments for charts improve delivery performance and reliability

## Design Patterns

- **Adapter Pattern:** Used for chart generation services
- **Factory Pattern:** For notifiers and schedulers creation
- **Strategy Pattern:** For fallback mechanisms in service failures
- **Dependency Inversion:** Services depend on behaviors rather than concrete implementations
- **Registry Pattern:** For tracking and managing scheduler instances

## Deployment & Operations

- **Containerization:**  
  - Each component (Elixir backend, Chart Service, Frontend) is containerized
- **CI/CD:**  
  - GitHub Actions workflows automate building, testing, and deployment
- **Monitoring & Error Handling:**  
  - Integrated logging and error classification ensure issues are captured and retried when transient
  - Health metrics for chart service and disk usage

## Future Enhancements

- Complete migration from external QuickChart.io to internal Node.js chart service
- Implement structured data types for all remaining API integrations
- Enhance caching strategies for consistency across all data sources
- Improve test coverage, especially for API integrations and schedulers
- Implement more granular feature flags for selective enabling of capabilities