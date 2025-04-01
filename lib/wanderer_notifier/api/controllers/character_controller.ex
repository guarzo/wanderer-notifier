defmodule WandererNotifier.Api.Controllers.CharacterController do
  @moduledoc """
  Controller for character-related endpoints.
  """
  use WandererNotifier.Api.Controllers.BaseController

  alias WandererNotifier.Api.Character.KillsService

  # Get character kills
  get "/kills/:character_id" do
    case KillsService.get_kills_for_character(character_id) do
      {:ok, kills} -> send_success_response(conn, kills)
      {:error, reason} -> send_error_response(conn, 400, reason)
    end
  end

  match _ do
    send_error_response(conn, 404, "Not found")
  end
end
