defmodule WandererNotifier.Api.ApiPipeline do
  @moduledoc """
  Shared API pipeline for all Plug-based API controllers.
  Use this module to DRY up plug setup in each controller.
  """
  defmacro __using__(_opts) do
    quote do
      use Plug.Router
      import Plug.Conn

      plug :match
      plug Plug.Parsers,
        parsers: [:json],
        pass: ["application/json"],
        json_decoder: Jason
      plug :dispatch
    end
  end
end
