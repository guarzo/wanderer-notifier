defmodule WandererNotifier.Api.Controllers.ControllerHelpers do
  @moduledoc """
  Shared controller functionality for API endpoints.
  """

  defmacro __using__(_) do
    quote do
      import Plug.Conn
      import WandererNotifier.Api.Helpers
    end
  end
end
