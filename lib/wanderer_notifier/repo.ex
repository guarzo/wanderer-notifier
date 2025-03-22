defmodule WandererNotifier.Repo do
  use Ecto.Repo,
    otp_app: :wanderer_notifier,
    adapter: Ecto.Adapters.Postgres
end
