defmodule WandererNotifier.Api.Controllers.CharacterController do
  @moduledoc """
  Controller for character-related endpoints.
  """
  use Plug.Router
  import Plug.Conn

  alias WandererNotifier.Api.Character.KillsService

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  # Get character kills
  get "/kills/:character_id" do
    case KillsService.get_kills_for_character(character_id) do
      {:ok, kills} -> send_json_response(conn, 200, kills)
      {:error, reason} -> send_json_response(conn, 400, %{error: reason})
    end
  end

  match _ do
    send_json_response(conn, 404, %{error: "Not found"})
  end

  defp send_json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
