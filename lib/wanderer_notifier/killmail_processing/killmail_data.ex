defmodule WandererNotifier.KillmailProcessing.KillmailData do
  @moduledoc """
  @deprecated Please use WandererNotifier.Killmail.Core.Data instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Core.Data.

  This is a compatibility layer that transparently forwards all struct and function
  calls to the new module to ease migration.
  """

  # Get the struct keys from the Data module
  @fields Map.keys(%WandererNotifier.Killmail.Core.Data{})
          |> Enum.filter(fn k -> k != :__struct__ end)

  defstruct @fields

  # Delegate all type specs to the new module
  @type t :: WandererNotifier.Killmail.Core.Data.t()

  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Public API

  @doc """
  Creates a KillmailData struct from raw zKillboard and ESI data.
  @deprecated Use WandererNotifier.Killmail.Core.Data.from_zkb_and_esi/2 instead
  """
  def from_zkb_and_esi(zkb_data, esi_data) do
    case Data.from_zkb_and_esi(zkb_data, esi_data) do
      {:ok, data} ->
        # Convert the struct to our type for backward compatibility
        struct(__MODULE__, Map.from_struct(data))

      {:error, reason} ->
        AppLogger.kill_error("Error creating KillmailData from ZKB/ESI: #{inspect(reason)}")
        # Return empty struct for backward compatibility
        struct(__MODULE__, %{})
    end
  end

  @doc """
  Creates a KillmailData struct from a resource record.
  @deprecated Use WandererNotifier.Killmail.Core.Data.from_resource/1 instead
  """
  def from_resource(resource) do
    case Data.from_resource(resource) do
      {:ok, data} ->
        # Convert the struct to our type for backward compatibility
        struct(__MODULE__, Map.from_struct(data))

      {:error, reason} ->
        AppLogger.kill_error("Error creating KillmailData from resource: #{inspect(reason)}")
        # Return empty struct for backward compatibility
        struct(__MODULE__, %{})
    end
  end

  @doc """
  Creates a KillmailData struct from a map.
  @deprecated Use WandererNotifier.Killmail.Core.Data.from_map/1 instead
  """
  def from_map(map) do
    case Data.from_map(map) do
      {:ok, data} ->
        # Convert the struct to our type for backward compatibility
        struct(__MODULE__, Map.from_struct(data))

      {:error, reason} ->
        AppLogger.kill_error("Error creating KillmailData from map: #{inspect(reason)}")
        # Return empty struct for backward compatibility
        struct(__MODULE__, %{})
    end
  end

  @doc """
  Merges in data from an existing KillmailData struct.
  @deprecated Use WandererNotifier.Killmail.Core.Data.merge/2 instead
  """
  def merge(data, other_data) do
    case Data.merge(convert_to_data(data), convert_to_data(other_data)) do
      {:ok, merged_data} ->
        # Convert the struct to our type for backward compatibility
        struct(__MODULE__, Map.from_struct(merged_data))

      {:error, reason} ->
        AppLogger.kill_error("Error merging KillmailData: #{inspect(reason)}")
        # Return original data for backward compatibility
        data
    end
  end

  # Helper function to convert KillmailData to Data if needed
  defp convert_to_data(%__MODULE__{} = killmail_data) do
    struct(Data, Map.from_struct(killmail_data))
  end

  defp convert_to_data(%Data{} = data), do: data
  defp convert_to_data(other), do: other
end
