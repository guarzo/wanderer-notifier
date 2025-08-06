defmodule WandererNotifierWeb.Endpoint do
  @moduledoc """
  Phoenix endpoint for WandererNotifier with minimal configuration.

  Provides basic HTTP functionality and WebSocket support for channels
  without the full Phoenix web stack (no HTML, views, templates).
  """

  use Phoenix.Endpoint, otp_app: :wanderer_notifier

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_wanderer_notifier_key",
    signing_salt: WandererNotifier.Shared.Env.get("SESSION_SIGNING_SALT", "wanderer_salt"),
    same_site: "Lax"
  ]

  # Phoenix channels removed - this app is a consumer, not a provider

  # Serve at "/" the static files from "priv/static" directory.
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :wanderer_notifier,
    gzip: false,
    only: ~w(assets css js fonts images favicon.ico robots.txt)
  )

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
  end

  # LiveDashboard request logger (disabled for minimal setup)
  # plug Phoenix.LiveDashboard.RequestLogger,
  #   param_key: "request_logger",
  #   cookie_key: "request_logger"

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Plug.Logger, log: &__MODULE__.should_log_request?/1)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(WandererNotifierWeb.Router)

  @doc """
  Returns static file paths for the endpoint.
  Since we're not using the full Phoenix web stack, this is minimal.
  """
  def static_paths, do: ~w(assets css js fonts images favicon.ico robots.txt)

  @doc """
  Determines if code reloading is enabled.
  """
  def code_reloading? do
    WandererNotifier.Shared.Env.get_app_config(
      :wanderer_notifier,
      :code_reloader,
      "CODE_RELOADER_ENABLED",
      false
    )
  end

  @doc """
  Determines whether to log a request based on its path.
  Returns false for health check endpoints to reduce log noise.
  """
  def should_log_request?(%Plug.Conn{request_path: path}) do
    path not in ["/api/health", "/health", "/api/status"]
  end
end
