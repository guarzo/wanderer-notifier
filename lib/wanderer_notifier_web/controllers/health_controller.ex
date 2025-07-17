defmodule WandererNotifierWeb.HealthController do
  @moduledoc """
  Health check controller for monitoring and load balancer integration.
  """

  use Phoenix.Controller, formats: [:json]

  @doc """
  Simple health check endpoint.
  Returns basic system status and uptime information.
  """
  def check(conn, _params) do
    uptime_seconds =
      System.monotonic_time(:second) -
        Application.get_env(:wanderer_notifier, :start_time, System.monotonic_time(:second))

    status = %{
      status: "healthy",
      uptime_seconds: uptime_seconds,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:wanderer_notifier, :vsn) |> to_string()
    }

    json(conn, status)
  end
end
