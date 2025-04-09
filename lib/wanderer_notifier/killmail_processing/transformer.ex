defmodule WandererNotifier.KillmailProcessing.Transformer do
  @moduledoc """
  Transformer module for killmail data conversion.

  This module provides functions to convert between different killmail data
  formats, ensuring consistent transformation at well-defined points in the
  pipeline. It centralizes conversion logic to reduce duplication and
  inconsistencies.
  """

  alias WandererNotifier.KillmailProcessing.{Extractor, KillmailData}
  alias WandererNotifier.KillmailProcessing.Validator
  alias WandererNotifier.Resources.Killmail, as: KillmailResource

  @doc """
  Converts any killmail format to a KillmailData struct.

  This is the primary entry point for standardizing killmail data formats.
  Use this function whenever you need to ensure you're working with a
  consistent killmail representation.

  ## Parameters
    - killmail: Any supported killmail format (map, KillmailResource, etc.)

  ## Returns
    - %KillmailData{} struct with standardized fields
  """
  def to_killmail_data(killmail)

  # Already a KillmailData struct, just return it
  def to_killmail_data(%KillmailData{} = killmail), do: killmail

  # Convert KillmailResource to KillmailData
  def to_killmail_data(%KillmailResource{} = resource) do
    KillmailData.from_resource(resource)
  end

  # Convert raw data to KillmailData
  def to_killmail_data(data) when is_map(data) do
    # Extract core data using Extractor
    killmail_id = Extractor.get_killmail_id(data)
    system_id = Extractor.get_system_id(data)
    system_name = Extractor.get_system_name(data)
    kill_time = Extractor.get_kill_time(data)
    zkb_data = Extractor.get_zkb_data(data)
    victim = Extractor.get_victim(data)
    attackers = Extractor.get_attackers(data)

    # Build a standardized KillmailData struct
    %KillmailData{
      killmail_id: killmail_id,
      solar_system_id: system_id,
      solar_system_name: system_name,
      kill_time: kill_time,
      zkb_data: zkb_data,
      esi_data: Map.get(data, :esi_data),
      victim: victim,
      attackers: attackers,
      persisted: Map.get(data, :persisted, false),
      metadata: Map.get(data, :metadata, %{})
    }
  end

  # Default for nil or non-map values
  def to_killmail_data(nil), do: nil
  def to_killmail_data(_), do: nil

  @doc """
  Converts a killmail to the normalized format expected by the database.

  This is a utility function that builds on the Validator.normalize_killmail
  function but ensures the input is first converted to a standard KillmailData
  format for consistent processing.

  ## Parameters
    - killmail: Any supported killmail format

  ## Returns
    - Map with normalized fields ready for database persistence
  """
  def to_normalized_format(killmail) do
    # First ensure we have a standardized killmail format
    killmail_data = to_killmail_data(killmail)

    # Then use the validator's normalize function
    Validator.normalize_killmail(killmail_data)
  end
end
