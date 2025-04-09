defmodule WandererNotifier.Resources.Api do
  @moduledoc """
  Ash Domain for WandererNotifier resources.
  Defines the interface for interacting with the application's resources.
  """

  use Ash.Domain, validate_config_inclusion?: false
  @behaviour WandererNotifier.Resources.ApiBehaviour

  resources do
    resource(WandererNotifier.Resources.Killmail)
    resource(WandererNotifier.Resources.KillmailCharacterInvolvement)
    resource(WandererNotifier.Resources.KillmailStatistic)
    resource(WandererNotifier.Resources.KillTrackingHistory)
    resource(WandererNotifier.Resources.TrackedCharacter)
    resource(WandererNotifier.Resources.KillmailPersistence)
    resource(WandererNotifier.Resources.KillmailAggregation)
  end

  # Public interface for resource operations
  # These delegate to Ash functions

  @impl true
  def read(query, opts \\ []) do
    Ash.read(query, opts)
  end

  def create(resource, attributes, opts \\ []) do
    Ash.create(resource, attributes, opts)
  end

  def update(resource, id, attributes, opts \\ []) do
    # In Ash, update is called on records, not just IDs
    # First read the record, then update it
    case Ash.get(resource, id) do
      {:ok, record} -> Ash.update(record, attributes, opts)
      error -> error
    end
  end

  def destroy(resource, id, opts \\ []) do
    # In Ash, destroy is called on records, not just IDs
    # First read the record, then destroy it
    case Ash.get(resource, id) do
      {:ok, record} -> Ash.destroy(record, opts)
      error -> error
    end
  end
end
