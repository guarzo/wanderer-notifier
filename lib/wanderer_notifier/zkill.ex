defmodule WandererNotifier.ZKill do
  @moduledoc """
  ZKillboard integration context.

  This module serves as the main entry point for all ZKillboard-related functionality.
  It provides functions to access killmail data and interact with the ZKillboard API.
  """

  alias WandererNotifier.ZKill.Client
  alias WandererNotifier.ZKill.Killmail
  alias WandererNotifier.ZKill.Parser
  alias WandererNotifier.ZKill.Websocket
  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Gets a single killmail by its ID.

  ## Parameters
    - kill_id: The killmail ID

  ## Returns
    - {:ok, killmail} on success where killmail is a Killmail struct
    - {:error, reason} on failure
  """
  def get_killmail(kill_id) do
    AppLogger.api_debug("ZKill getting killmail", %{kill_id: kill_id})

    with {:ok, data} <- Client.get_single_killmail(kill_id),
         {:ok, killmail} <- Killmail.from_api(data) do
      {:ok, killmail}
    end
  end

  @doc """
  Gets recent kills with an optional limit.

  ## Parameters
    - limit: The number of recent kills to fetch (default: 10)

  ## Returns
    - {:ok, kills} on success where kills is a list of Killmail structs
    - {:error, reason} on failure
  """
  def get_recent_kills(limit \\ 10) do
    AppLogger.api_debug("ZKill getting recent kills", %{limit: limit})

    with {:ok, data} <- Client.get_recent_kills(limit),
         {:ok, parsed} <- Parser.parse_killmails(data) do
      killmails = Enum.map(parsed, &Killmail.from_map/1)
      {:ok, killmails}
    end
  end

  @doc """
  Gets kills for a specific system with an optional limit.

  ## Parameters
    - system_id: The system ID to fetch kills for
    - limit: The number of kills to fetch (default: 5)

  ## Returns
    - {:ok, kills} on success where kills is a list of Killmail structs
    - {:error, reason} on failure
  """
  def get_system_kills(system_id, limit \\ 5) do
    AppLogger.api_debug("ZKill getting system kills", %{system_id: system_id, limit: limit})

    with {:ok, data} <- Client.get_system_kills(system_id, limit),
         {:ok, parsed} <- Parser.parse_killmails(data) do
      killmails = Enum.map(parsed, &Killmail.from_map/1)
      {:ok, killmails}
    end
  end

  @doc """
  Gets kills for a specific character.

  ## Parameters
    - character_id: The character ID to fetch kills for
    - date_range: Map with :start and :end DateTime (optional)
    - limit: Maximum number of kills to fetch (default: 100)

  ## Returns
    - {:ok, kills} on success where kills is a list of Killmail structs
    - {:error, reason} on failure
  """
  def get_character_kills(character_id, date_range \\ nil, limit \\ 100) do
    AppLogger.api_debug("ZKill getting character kills", %{
      character_id: character_id,
      limit: limit,
      date_range: date_range
    })

    with {:ok, data} <- Client.get_character_kills(character_id, date_range, limit),
         {:ok, parsed} <- Parser.parse_killmails(data) do
      killmails = Enum.map(parsed, &Killmail.from_map/1)
      {:ok, killmails}
    end
  end

  @doc """
  Starts the ZKillboard websocket connection.

  ## Parameters
    - parent: The parent process to receive messages

  ## Returns
    - {:ok, pid} if successful
    - {:error, reason} if connection fails
  """
  def start_websocket(parent) do
    AppLogger.websocket_debug("Starting ZKill websocket", %{parent: inspect(parent)})
    Websocket.start_link(parent)
  end

  @doc """
  Parses a websocket message from ZKillboard.

  ## Parameters
    - message: The raw message from the websocket

  ## Returns
    - {:ok, parsed_message} on success
    - {:error, reason} on failure
  """
  def parse_websocket_message(message) do
    Parser.parse_websocket_message(message)
  end
end
