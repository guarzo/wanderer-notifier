defmodule WandererNotifier.Logger.StructuredLogger do
  @moduledoc """
  Macros for structured logging with automatic metadata extraction.

  This module provides convenient macros that automatically include
  common metadata fields based on the context.

  ## Usage

  ```elixir
  import WandererNotifier.Logger.StructuredLogger

  # In a module that processes killmails
  def process_killmail(killmail) do
    log_info "Processing killmail", killmail: killmail do
      # Automatically extracts kill_id, system_id, victim.character_id
    end
    
    # Or with custom metadata
    log_debug "Killmail validation", 
      killmail: killmail,
      custom: "value" do
      # Merges automatic extraction with custom metadata
    end
  end

  # In a module that handles characters
  def update_character(character_id) do
    log_warn "Character not found", character_id: character_id do
      # Automatically includes character_id in metadata
    end
  end
  ```
  """

  alias WandererNotifier.Logger.Logger
  alias WandererNotifier.Logger.MetadataKeys

  @doc """
  Logs at info level with structured metadata.
  """
  defmacro log_info(message, metadata \\ []) do
    quote do
      require WandererNotifier.Logger.Logger

      metadata = unquote(__MODULE__).extract_metadata(unquote(metadata))
      Logger.info(unquote(message), metadata)
    end
  end

  @doc """
  Logs at debug level with structured metadata.
  """
  defmacro log_debug(message, metadata \\ []) do
    quote do
      require WandererNotifier.Logger.Logger

      metadata = unquote(__MODULE__).extract_metadata(unquote(metadata))
      Logger.debug(unquote(message), metadata)
    end
  end

  @doc """
  Logs at warning level with structured metadata.
  """
  defmacro log_warn(message, metadata \\ []) do
    quote do
      require WandererNotifier.Logger.Logger

      metadata = unquote(__MODULE__).extract_metadata(unquote(metadata))
      Logger.warn(unquote(message), metadata)
    end
  end

  @doc """
  Logs at error level with structured metadata.
  """
  defmacro log_error(message, metadata \\ []) do
    quote do
      require WandererNotifier.Logger.Logger

      metadata = unquote(__MODULE__).extract_metadata(unquote(metadata))
      Logger.error(unquote(message), metadata)
    end
  end

  @doc """
  Extracts metadata from various data structures.

  Automatically extracts common fields from known structures:
  - Killmails: kill_id, system_id, victim character_id
  - Characters: character_id, corporation_id, alliance_id
  - Systems: system_id, system_name
  - HTTP responses: status_code, url
  - Errors: error, reason
  """
  def extract_metadata(metadata) when is_list(metadata) do
    Enum.reduce(metadata, [], fn {key, value}, acc ->
      acc ++ extract_from_value(key, value)
    end)
  end

  def extract_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.to_list()
    |> extract_metadata()
  end

  def extract_metadata(_), do: []

  # Extract metadata from known structures
  defp extract_from_value(:killmail, %{} = killmail) do
    base = []

    base =
      if kill_id =
           safe_get_in(killmail, ["killmail_id"]) || safe_get_in(killmail, [:killmail_id]),
         do: [{MetadataKeys.kill_id(), kill_id} | base],
         else: base

    base =
      if system_id =
           safe_get_in(killmail, ["solar_system_id"]) || safe_get_in(killmail, [:solar_system_id]),
         do: [{MetadataKeys.system_id(), system_id} | base],
         else: base

    base =
      if character_id =
           safe_get_in(killmail, ["victim", "character_id"]) ||
             safe_get_in(killmail, [:victim, :character_id]),
         do: [{MetadataKeys.character_id(), character_id} | base],
         else: base

    base
  end

  defp extract_from_value(:character, %{} = character) do
    base = []

    base =
      if character_id =
           safe_get_in(character, ["character_id"]) || safe_get_in(character, [:character_id]),
         do: [{MetadataKeys.character_id(), character_id} | base],
         else: base

    base =
      if corp_id =
           safe_get_in(character, ["corporation_id"]) || safe_get_in(character, [:corporation_id]),
         do: [{MetadataKeys.corporation_id(), corp_id} | base],
         else: base

    base =
      if alliance_id =
           safe_get_in(character, ["alliance_id"]) || safe_get_in(character, [:alliance_id]),
         do: [{MetadataKeys.alliance_id(), alliance_id} | base],
         else: base

    base
  end

  defp extract_from_value(:system, %{} = system) do
    base = []

    base =
      if system_id = safe_get_in(system, ["system_id"]) || safe_get_in(system, [:system_id]),
        do: [{MetadataKeys.system_id(), system_id} | base],
        else: base

    base =
      if system_name = safe_get_in(system, ["name"]) || safe_get_in(system, [:name]),
        do: [{MetadataKeys.system_name(), system_name} | base],
        else: base

    base
  end

  defp extract_from_value(:response, %{} = response) do
    base = []

    base =
      if status = safe_get_in(response, [:status]) || safe_get_in(response, [:status_code]),
        do: [{MetadataKeys.status_code(), status} | base],
        else: base

    base =
      if url = safe_get_in(response, [:url]) || safe_get_in(response, [:request_url]),
        do: [{MetadataKeys.url(), url} | base],
        else: base

    base
  end

  defp extract_from_value(:error, error) do
    [{MetadataKeys.error(), inspect(error)}]
  end

  defp extract_from_value(:reason, reason) do
    [{MetadataKeys.reason(), inspect(reason)}]
  end

  # IDs can be passed directly
  defp extract_from_value(:character_id, id) when is_integer(id) or is_binary(id) do
    [{MetadataKeys.character_id(), id}]
  end

  defp extract_from_value(:system_id, id) when is_integer(id) or is_binary(id) do
    [{MetadataKeys.system_id(), id}]
  end

  defp extract_from_value(:kill_id, id) when is_integer(id) or is_binary(id) do
    [{MetadataKeys.kill_id(), id}]
  end

  defp extract_from_value(:corporation_id, id) when is_integer(id) or is_binary(id) do
    [{MetadataKeys.corporation_id(), id}]
  end

  defp extract_from_value(:alliance_id, id) when is_integer(id) or is_binary(id) do
    [{MetadataKeys.alliance_id(), id}]
  end

  # Default case - pass through
  defp extract_from_value(key, value) do
    [{key, value}]
  end

  # Helper to safely get nested values
  defp safe_get_in(data, keys) when is_map(data) do
    Kernel.get_in(data, keys)
  rescue
    _ -> nil
  end
end
