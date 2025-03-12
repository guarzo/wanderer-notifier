# License and Bot Registration Flow

## Overview

The license validation and bot registration system provides a robust mechanism for validating licenses, managing feature access based on license tiers, and registering bots with the License Manager service. This implementation follows a modular design with clear separation of concerns.

The system allows WandererNotifier to validate its license key with a central License Manager service, ensuring that only authorized instances can access premium features. It also supports bot registration, which associates a bot instance with a specific license key, enabling usage tracking and management.

## Application Flow

### 1. Application Startup

- The `WandererNotifier.Application` initializes the supervision tree
- The `WandererNotifier.License` GenServer starts as part of this tree
- After the supervision tree is established, license validation and bot registration are triggered
- The application continues to run regardless of license status, but with limited functionality if invalid

### 2. License Validation

- The `WandererNotifier.License` GenServer initializes with an invalid state
- It schedules a periodic refresh (every 24 hours) to handle license expiration or changes
- During initialization, it immediately performs an initial validation
- The validation process retrieves the license key and calls the License Manager API
- The validation result (including features and tier once they exist) is stored in the GenServer's state

### 3. Bot Registration

- If the license is valid, the application attempts to register the bot
- The registration process retrieves the license key and registration token
- If the registration token is missing, registration is skipped with a warning
- Otherwise, it calls the License Manager API to register the bot
- The registration associates the bot with the license in the License Manager
- Registration failures are logged but don't prevent the application from starting

### 4. Feature Access Control (future work)

- Features can be conditionally enabled based on license tier or specific feature flags
- Premium features are only available for "premium" or "enterprise" license tiers
- The application gracefully degrades functionality when the license is invalid


## Configuration

- The system is configured through environment variables:
  - `LICENSE_KEY`: The license key for validation
  - `LICENSE_MANAGER_API_URL`: The License Manager API URL
  - `LICENSE_MANAGER_AUTH_KEY`: Authentication key for the API
  - `BOT_REGISTRATION_TOKEN`: Optional token for bot registration
- These variables are loaded in `config/runtime.exs` and accessed through the `WandererNotifier.Config` module
