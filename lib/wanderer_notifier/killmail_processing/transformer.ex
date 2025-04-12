defmodule WandererNotifier.KillmailProcessing.Transformer do
  @moduledoc """
  Transformer module for killmail data conversion.

  @deprecated Please use WandererNotifier.Killmail.Utilities.Transformer instead

  This module is deprecated and will be removed in a future release.
  All functionality has been moved to WandererNotifier.Killmail.Utilities.Transformer.
  """

  require Logger

  alias WandererNotifier.KillmailProcessing.DataAccess
  alias WandererNotifier.KillmailProcessing.KillmailData
  alias WandererNotifier.KillmailProcessing.Validator
  alias WandererNotifier.Resources.Killmail, as: KillmailResource
  alias WandererNotifier.Killmail.Core.Data
  alias WandererNotifier.Killmail.Utilities.Transformer, as: NewTransformer

  @doc """
  Converts any killmail format to a KillmailData struct.
  @deprecated Use WandererNotifier.Killmail.Utilities.Transformer.to_killmail_data/1 instead

  This is the primary entry point for standardizing killmail data formats.
  Use this function whenever you need to ensure you're working with a
  consistent killmail representation.

  ## Parameters
    - killmail: Any supported killmail format (map, KillmailResource, etc.)

  ## Returns
    - %KillmailData{} struct with standardized fields
  """
  def to_killmail_data(killmail) do
    Logger.warning("Using deprecated Transformer.to_killmail_data/1, please update your code")

    # Already a KillmailData struct, just return it
    case killmail do
      %KillmailData{} ->
        killmail

      # Delegate to the new implementation
      _ ->
        case NewTransformer.to_killmail_data(killmail) do
          {:ok, new_data} -> convert_to_old_format(new_data)
          %Data{} = new_data -> convert_to_old_format(new_data)
          {:error, reason} -> handle_error(reason)
          other -> other
        end
    end
  end

  @doc """
  Converts a killmail to the normalized format expected by the database.
  @deprecated Use WandererNotifier.Killmail.Utilities.Transformer.to_normalized_format/1 instead

  This function transforms a killmail into a normalized map format suitable
  for database persistence, extracting essential fields.

  ## Parameters
    - killmail: Any supported killmail format

  ## Returns
    - Map with normalized fields ready for database persistence
  """
  def to_normalized_format(killmail) do
    Logger.warning("Using deprecated Transformer.to_normalized_format/1, please update your code")

    # Delegate to the new implementation
    NewTransformer.to_normalized_format(killmail)
  end

  # Helper functions

  # Convert a Data struct to a KillmailData struct for backward compatibility
  defp convert_to_old_format(%Data{} = new_data) do
    struct(KillmailData, Map.from_struct(new_data))
  end

  # Handle errors and convert to appropriate return values
  defp handle_error(reason) do
    Logger.error("Error in Transformer: #{inspect(reason)}")
    nil
  end
end
