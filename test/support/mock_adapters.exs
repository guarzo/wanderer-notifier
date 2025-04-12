# Define behaviors for mocking
defmodule WandererNotifier.Killmail.Core.ValidatorBehaviour do
  @callback validate(WandererNotifier.Killmail.Core.Data.t()) ::
              :ok | {:error, list({atom(), String.t()})} | {:skip, String.t()}
  @callback log_validation_errors(
              WandererNotifier.Killmail.Core.Data.t(),
              list({atom(), String.t()})
            ) :: :ok
  @callback has_minimum_required_data?(WandererNotifier.Killmail.Core.Data.t()) :: boolean()
end

defmodule WandererNotifier.Killmail.Processing.CacheBehaviour do
  @callback in_cache?(integer()) :: boolean()
  @callback cache(WandererNotifier.Killmail.Core.Data.t()) ::
              {:ok, WandererNotifier.Killmail.Core.Data.t()} | {:error, any()}
end

defmodule WandererNotifier.Killmail.Processing.EnrichmentBehaviour do
  @callback enrich(WandererNotifier.Killmail.Core.Data.t()) ::
              {:ok, WandererNotifier.Killmail.Core.Data.t()} | {:error, any()}
end

defmodule WandererNotifier.Killmail.Processing.NotificationDeterminerBehaviour do
  @callback should_notify?(WandererNotifier.Killmail.Core.Data.t()) ::
              {:ok, {boolean(), String.t()}} | {:error, any()}
end

defmodule WandererNotifier.Killmail.Processing.NotificationBehaviour do
  @callback notify(WandererNotifier.Killmail.Core.Data.t()) :: :ok | {:error, any()}
end

defmodule WandererNotifier.Killmail.Processing.PersistenceBehaviour do
  @callback persist(WandererNotifier.Killmail.Core.Data.t()) ::
              {:ok, WandererNotifier.Killmail.Core.Data.t()} | {:error, any()}
end

defmodule WandererNotifier.Killmail.Processing.ProcessorBehaviour do
  @callback process_killmail(map() | WandererNotifier.Killmail.Core.Data.t(), map()) ::
              {:ok, WandererNotifier.Killmail.Core.Data.t()}
              | {:ok, :skipped}
              | {:error, any()}
end
