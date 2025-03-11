# WandererNotifier Implementation Tasks


# Combined License & Bot Registration Integration Tasks

- [ ] **Update Environment & Configuration**
  - [ ] Add the `LICENSE_KEY` variable to `.env.example` and update documentation.
  - [ ] (Optional) Add `BOT_REGISTRATION_TOKEN` if required for LM registration.
  - [ ] Ensure that `LICENSE_MANAGER_API_URL` and `LICENSE_MANAGER_AUTH_KEY` are defined in your environment.
  - [ ] Update `config/runtime.exs` to load these new environment variables along with existing ones.

- [ ] **Review the License Manager Code Base**
  - [ ] Examine the `Wanderer.LicenseManager.Client` module to understand its functions:
    - `create_license/1`
    - `update_license/2`
    - `validate_license/1`
  - [ ] Review how error handling and caching are implemented to manage API responses.

- [ ] **Integrate License Validation into Bot Startup**
  - [ ] In `WandererNotifier.Application.start/2`, retrieve `LICENSE_KEY` from the environment.
  - [ ] Call `Wanderer.LicenseManager.Client.validate_license/1` using the retrieved key.
  - [ ] Process the validation result:
    - If valid, extract any extra configuration (e.g., premium feature flags) and store it in the application state.
    - If invalid, log a clear error and determine fallback behavior.

- [ ] **(Optional) Create a Dedicated License Module**
  - [ ] If additional abstraction is desired, create a module (e.g., `WandererNotifier.License`) that wraps the License Manager API calls.
  - [ ] Implement a `validate/1` function that uses `Wanderer.LicenseManager.Client.validate_license/1` internally.

- [ ] **Incorporate Bot Registration**
  - [ ] Determine if a separate bot registration process is needed (check if license manager code already supports bot associations).
  - [ ] Create or update a module (e.g., `WandererNotifier.BotRegistration`) that:
    - Uses the License Manager API functions to register the bot with LM.
    - Differentiates bots by type so that multiple corps can use the same bot token while having distinct license keys.
  - [ ] Ensure that the registration logic is executed as a one-off startup step (or manually triggered) and log the outcome.

- [ ] **Condition Feature Activation Based on License Status**
  - [ ] Store the license validation result (activation flag or extra configuration) in the application state or configuration.
  - [ ] Use this flag to conditionally enable premium features within the bot.
  - [ ] Add logging for both valid and invalid license scenarios.

- [ ] **Count by Bot Type Instead of Running Instances**
  - [ ] Add configuration or logic to identify the "bot type" (using a new configuration variable or derived value).
  - [ ] Modify the registration logic to count and register by bot type so that multiple instances sharing the same bot token can operate with different license keys.

- [ ] **Update Documentation**
  - [ ] Update the README, project overview, and integration guides to explain the new license validation and bot registration process.
  - [ ] Document that updating the license key requires modifying the environment variables and restarting the bot.
  - [ ] Add clear comments in the new modules and startup routines to aid future maintenance.

- [ ] **Testing & Error Handling**
  - [ ] Write unit tests for license validation functions (e.g., `Wanderer.LicenseManager.Client.validate_license/1`) and any new registration logic.
  - [ ] Test both successful validation and failure cases (e.g., invalid or expired licenses).
  - [ ] Ensure robust error handling and logging for both license validation and bot registration failures.

- [ ] **Deployment and Restart Strategy**
  - [ ] Document the process for updating the license key and restarting the bot.
  - [ ] (Optional) Consider adding a periodic check or an admin command to re-validate the license during runtime.


## Structure Timer Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.Timers.Service` module
    - [ ] Add function to fetch from `/api/map/structure-timers` endpoint
    - [ ] Handle query params: `map_id`, `slug`, `system_id`
    - [ ] Parse response schema with required fields: `system_id`, `solar_system_id`, `name`, `status`
  - [ ] Create `WandererNotifier.Timers.State` module
    - [ ] Define timer state struct with fields matching API response
    - [ ] Add functions to compare timer states and detect changes

- [ ] Implement timer tracking
  - [ ] Add timer state comparison logic for:
    - [ ] New timers (not in previous state)
    - [ ] Changed timers (status or end_time changed)
    - [ ] Expiring timers (end_time approaching)
  - [ ] Add timer metadata tracking:
    - [ ] `character_eve_id`
    - [ ] `owner_name`/`owner_ticker`
    - [ ] `structure_type`
    - [ ] `solar_system_name`

## Kill Activity Summary Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.KillSummary.Service` module
    - [ ] Add function to fetch from `/api/map/systems-kills` endpoint
    - [ ] Handle query params: `map_id`, `slug`, `hours`
  - [ ] Create `WandererNotifier.KillSummary.Aggregator` module
    - [ ] Parse kill details from response:
      - [ ] `kill_id`
      - [ ] `kill_time`
      - [ ] `ship_name`/`ship_type_id`
      - [ ] `victim_name`/`victim_id`

- [ ] Implement kill tracking
  - [ ] Add aggregation functions for:
    - [ ] Kills by system
    - [ ] Kills by ship type
    - [ ] Kills by time period
  - [ ] Add threshold detection for high activity periods

## ACL Change Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.ACL.Monitor` module
    - [ ] Add function to fetch from `/api/map/acls` endpoint
    - [ ] Handle query params: `map_id`, `slug`
  - [ ] Create `WandererNotifier.ACL.Diff` module
    - [ ] Track ACL member changes via `/api/acls/{acl_id}/members` endpoint
    - [ ] Monitor member role updates via PUT endpoint
    - [ ] Track member deletions via DELETE endpoint

- [ ] Implement ACL tracking
  - [ ] Add change detection for:
    - [ ] New members (POST to members endpoint)
    - [ ] Role changes (PUT to member endpoint)
    - [ ] Member removals (DELETE to member endpoint)
  - [ ] Track member metadata:
    - [ ] `eve_alliance_id`
    - [ ] `eve_corporation_id`
    - [ ] `eve_character_id`
    - [ ] `role`

## Character Activity Notifier
- [ ] Create base modules
  - [ ] Create `WandererNotifier.Character.Activity` module
    - [ ] Add function to fetch from `/api/map/characters` endpoint
    - [ ] Handle query params: `map_id`, `slug`
  - [ ] Create `WandererNotifier.Character.State` module
    - [ ] Track character metadata:
      - [ ] `alliance_name`/`alliance_ticker`
      - [ ] `corporation_name`/`corporation_ticker`
      - [ ] `name`
      - [ ] `tracked` status

- [ ] Implement activity tracking
  - [ ] Add tracking for:
    - [ ] Corporation changes
    - [ ] Alliance changes
    - [ ] Tracking status changes
  - [ ] Add character info lookup via `/api/characters` endpoint

## Shared Infrastructure Updates
- [ ] Add API client modules
  - [ ] Create `WandererNotifier.API.Client` module
    - [ ] Add authentication handling for bearer tokens
    - [ ] Add base URL configuration
    - [ ] Add error handling for common response codes
  - [ ] Create response schemas matching API documentation

- [ ] Add configuration options
  - [ ] Add map identification config (map_id or slug)
  - [ ] Add API authentication config
  - [ ] Add notification thresholds config
  - [ ] Add polling intervals config

## License Manager Integration

### 1. Environment & Configuration Setup
- [ ] Create configuration module
  ```elixir
  defmodule WandererNotifier.Config do
    @moduledoc """
    Configuration management for WandererNotifier
    """
    
    def license_key, do: get_env!(:license_key)
    def license_manager_url, do: get_env!(:license_manager_url)
    def license_manager_auth_key, do: get_env!(:license_manager_auth_key)
    def bot_registration_token, do: get_env(:bot_registration_token)
    
    defp get_env!(key), do: get_env(key) || raise "Missing #{key} configuration"
    defp get_env(key), do: Application.get_env(:wanderer_notifier, key)
  end
  ```

- [ ] Update `config/runtime.exs`:
  ```elixir
  config :wanderer_notifier,
    license_key: System.get_env("LICENSE_KEY"),
    license_manager_url: System.get_env("LICENSE_MANAGER_API_URL"),
    license_manager_auth_key: System.get_env("LICENSE_MANAGER_AUTH_KEY"),
    bot_registration_token: System.get_env("BOT_REGISTRATION_TOKEN")
  ```

- [ ] Create `.env.example`:
  ```bash
  LICENSE_KEY=your_license_key_here
  LICENSE_MANAGER_API_URL=https://license.example.com
  LICENSE_MANAGER_AUTH_KEY=your_auth_key_here
  BOT_REGISTRATION_TOKEN=optional_bot_token
  ```

### 2. License Manager Client Implementation
- [ ] Create `WandererNotifier.License` module:
  ```elixir
  defmodule WandererNotifier.License do
    @moduledoc """
    License validation and management for WandererNotifier
    """
    use GenServer
    require Logger
    alias Wanderer.LicenseManager.Client, as: LicenseClient
    
    @refresh_interval :timer.hours(24)
    
    # Client API
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
    
    def validate do
      GenServer.call(__MODULE__, :validate)
    end
    
    def status do
      GenServer.call(__MODULE__, :status)
    end
    
    # Server Implementation
    @impl true
    def init(_opts) do
      schedule_refresh()
      {:ok, %{valid: false}, {:continue, :initial_validation}}
    end
    
    @impl true
    def handle_continue(:initial_validation, state) do
      new_state = do_validate()
      {:noreply, new_state}
    end
    
    @impl true
    def handle_call(:validate, _from, _state) do
      new_state = do_validate()
      {:reply, new_state.valid, new_state}
    end
    
    @impl true
    def handle_call(:status, _from, state) do
      {:reply, state, state}
    end
    
    @impl true
    def handle_info(:refresh, _state) do
      schedule_refresh()
      new_state = do_validate()
      {:noreply, new_state}
    end
    
    defp schedule_refresh do
      Process.send_after(self(), :refresh, @refresh_interval)
    end
    
    defp do_validate do
      license_key = WandererNotifier.Config.license_key()
      
      case LicenseClient.validate_license(license_key) do
        {:ok, response} ->
          Logger.info("License validation successful")
          %{valid: true, details: response}
          
        {:error, reason} ->
          Logger.error("License validation failed: #{inspect(reason)}")
          %{valid: false, error: reason}
      end
    end
  end
  ```

### 3. Application Integration
- [ ] Update `WandererNotifier.Application`:
  ```elixir
  defmodule WandererNotifier.Application do
    use Application
    
    def start(_type, _args) do
      children = [
        WandererNotifier.License,
        # ... other children ...
      ]
      
      opts = [strategy: :one_for_one, name: WandererNotifier.Supervisor]
      case Supervisor.start_link(children, opts) do
        {:ok, pid} ->
          validate_license_or_halt()
          {:ok, pid}
        error ->
          error
      end
    end
    
    defp validate_license_or_halt do
      case WandererNotifier.License.validate() do
        true -> :ok
        false ->
          Logger.error("Invalid license. Shutting down.")
          System.stop(1)
      end
    end
  end
  ```

### 4. Feature Flag Implementation
- [ ] Create `WandererNotifier.Features` module:
  ```elixir
  defmodule WandererNotifier.Features do
    @moduledoc """
    Feature flag management based on license status
    """
    
    def enabled?(feature) do
      case WandererNotifier.License.status() do
        %{valid: true, details: %{features: features}} ->
          feature in features
        _ ->
          false
      end
    end
    
    def premium?(%{valid: true, details: %{tier: tier}}) do
      tier in ["premium", "enterprise"]
    end
    def premium?(_), do: false
  end
  ```

### 5. Testing
- [ ] Create test files:
  - [ ] `test/wanderer_notifier/license_test.exs`
  - [ ] `test/wanderer_notifier/features_test.exs`
  - [ ] `test/wanderer_notifier/config_test.exs`

- [ ] Add test helpers:
  ```elixir
  defmodule WandererNotifier.Test.Helpers do
    def setup_license_mock(response) do
      :ok = Application.put_env(:wanderer_notifier, :license_key, "test_key")
      Mox.stub(Wanderer.LicenseManager.ClientMock, :validate_license, fn _ -> response end)
    end
  end
  ```

### 6. Documentation
- [ ] Update README.md with license setup instructions
- [ ] Add module documentation with examples
- [ ] Create CONTRIBUTING.md with development setup guide

### 7. Deployment Updates
- [ ] Update deployment scripts to include new environment variables
- [ ] Add license validation to health check endpoints
- [ ] Create license renewal notification system 