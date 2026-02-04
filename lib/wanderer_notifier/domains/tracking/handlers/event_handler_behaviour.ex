defmodule WandererNotifier.Domains.Tracking.Handlers.EventHandlerBehaviour do
  @moduledoc """
  Behavior definition for tracking event handlers.

  Defines a common interface for character and system event handlers,
  enabling shared logic and consistent event processing patterns.
  """

  @doc """
  Handles entity added events.

  This callback is invoked when a new entity (character or system) is added to the map.
  The handler should extract the entity data, update the cache, and potentially send notifications.

  ## Parameters
  - `event` - The full event map containing payload and metadata
  - `map_slug` - The map identifier for logging and context

  ## Returns
  - `:ok` if the event was processed successfully
  - `{:error, reason}` if there was an error processing the event
  """
  @callback handle_entity_added(event :: map(), map_slug :: String.t()) :: :ok | {:error, term()}

  @doc """
  Handles entity removed events.

  This callback is invoked when an entity (character or system) is removed from the map.
  The handler should update the cache and potentially log the removal.

  ## Parameters
  - `event` - The full event map containing payload and metadata
  - `map_slug` - The map identifier for logging and context

  ## Returns
  - `:ok` if the event was processed successfully
  - `{:error, reason}` if there was an error processing the event
  """
  @callback handle_entity_removed(event :: map(), map_slug :: String.t()) ::
              :ok | {:error, term()}

  @doc """
  Handles entity updated events.

  This callback is invoked when an entity's metadata or properties are updated.
  The handler should update the cache and potentially send notifications or log the update.

  ## Parameters
  - `event` - The full event map containing payload and metadata
  - `map_slug` - The map identifier for logging and context

  ## Returns
  - `:ok` if the event was processed successfully
  - `{:error, reason}` if there was an error processing the event
  """
  @callback handle_entity_updated(event :: map(), map_slug :: String.t()) ::
              :ok | {:error, term()}
end
