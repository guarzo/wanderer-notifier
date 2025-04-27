defmodule WandererNotifier.ZKill.Parser do
  @moduledoc """
  Parser for ZKillboard API responses.
  Handles transforming the raw API data into structured, normalized formats.
  """

  alias WandererNotifier.Logger.Logger, as: AppLogger

  @doc """
  Parses a killmail from ZKillboard API.

  ## Parameters
    - data: The raw killmail data from ZKillboard

  ## Returns
    - {:ok, parsed_killmail} on success
    - {:error, reason} on failure
  """
  def parse_killmail(data) when is_map(data) do
    kill_id = Map.get(data, "killmail_id")
    zkb_data = Map.get(data, "zkb")

    with {:ok, parsed} <- validate_killmail(data, kill_id, zkb_data) do
      {:ok, normalize_killmail(parsed)}
    end
  end

  def parse_killmail(data) do
    {:error, {:invalid_format, :not_a_map}}
  end

  @doc """
  Parses a list of killmails from ZKillboard API.

  ## Parameters
    - data: List of raw killmail data from ZKillboard

  ## Returns
    - {:ok, parsed_killmails} on success
    - {:error, reason} on failure
  """
  def parse_killmails(data) when is_list(data) do
    parsed =
      data
      |> Enum.map(fn killmail ->
        case parse_killmail(killmail) do
          {:ok, parsed} -> parsed
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, parsed}
  end

  def parse_killmails(data) do
    {:error, {:invalid_format, :not_a_list}}
  end

  @doc """
  Parses a websocket message from ZKillboard.

  ## Parameters
    - message: The raw message from the websocket

  ## Returns
    - {:ok, parsed_message} on success
    - {:error, reason} on failure
  """
  def parse_websocket_message(message) when is_map(message) do
    kill_id = Map.get(message, "killID")
    hash = Map.get(message, "hash")

    cond do
      is_nil(kill_id) ->
        {:error, {:invalid_format, :missing_kill_id}}

      is_nil(hash) ->
        {:error, {:invalid_format, :missing_hash}}

      true ->
        {:ok, %{kill_id: kill_id, hash: hash}}
    end
  end

  def parse_websocket_message(message) do
    {:error, {:invalid_format, :websocket_message}}
  end

  # Private helper functions

  defp validate_killmail(data, nil, _) do
    {:error, {:invalid_format, :missing_kill_id}}
  end

  defp validate_killmail(data, _, nil) do
    {:error, {:invalid_format, :missing_zkb_data}}
  end

  defp validate_killmail(data, kill_id, zkb_data) do
    {:ok, data}
  end

  defp normalize_killmail(killmail) do
    # Ensure consistent structure
    normalized_zkb =
      killmail
      |> Map.get("zkb", %{})
      |> Map.new(fn {k, v} -> {k, v} end)

    # Always return a map with string keys for consistency
    Map.merge(
      %{
        "killmail_id" => Map.get(killmail, "killmail_id"),
        "zkb" => normalized_zkb
      },
      Map.drop(killmail, ["zkb"])
    )
  end
end
