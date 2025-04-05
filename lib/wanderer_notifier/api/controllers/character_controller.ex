defmodule WandererNotifier.Api.Controllers.CharacterController do
  @moduledoc """
  Controller for character-related endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController

  alias WandererNotifier.Api.Character.KillsService
  alias WandererNotifier.Logger.Logger, as: AppLogger

  # Get character kills
  get "/kills/:character_id" do
    case KillsService.get_kills_for_character(character_id) do
      {:ok, kills} -> send_success_response(conn, kills)
      {:error, reason} -> send_error_response(conn, 400, reason)
    end
  end

  # Get kills for all tracked characters
  get "/" do
    AppLogger.api_info("Received request to fetch kills for all tracked characters")
    all = Map.get(conn.params, "all", "false") == "true"

    if all do
      # Start the kill fetching process asynchronously
      Task.start(fn ->
        case KillsService.fetch_and_persist_all_tracked_character_kills() do
          {:ok, summary} ->
            AppLogger.api_info("Successfully fetched kills for all characters", summary: summary)

          {:error, reason} ->
            AppLogger.api_error("Failed to fetch kills for all characters",
              error: inspect(reason)
            )
        end
      end)

      # Respond immediately with a success status
      send_success_response(conn, %{
        success: true,
        message: "Kill fetching process started",
        details: %{
          status: "processing"
        }
      })
    else
      send_error_response(conn, 400, "Missing required parameter: all=true")
    end
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end
end
