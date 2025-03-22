defmodule WandererNotifier.Schedulers.Factory do
  @moduledoc """
  Factory module for creating schedulers based on configuration.

  This module provides functions to create the appropriate scheduler
  implementation based on the specified configuration.
  """

  require Logger

  @doc """
  Creates a scheduler module with the appropriate implementation.

  ## Parameters

  - `module_name` - The name of the module to create
  - `opts` - Options that define the scheduler behavior:
    - `:type` - The type of scheduler to create (`:interval` or `:time`)
    - `:default_interval` - For interval-based schedulers, the default interval in milliseconds
    - `:default_hour` - For time-based schedulers, the default hour (0-23)
    - `:default_minute` - For time-based schedulers, the default minute (0-59)
    - `:hour_env_var` - For time-based schedulers, the environment variable name for the hour
    - `:minute_env_var` - For time-based schedulers, the environment variable name for the minute
    - `:enabled_check` - Function that determines if the scheduler is enabled

  ## Returns

  Module definition code that can be evaluated

  ## Examples

      defmodule MyApp.MyScheduler do
        require WandererNotifier.Schedulers.Factory

        WandererNotifier.Schedulers.Factory.create_scheduler(
          type: :interval,
          default_interval: 3600000,
          enabled_check: &MyApp.Config.feature_enabled?/0
        )

        @impl true
        def execute(state) do
          # Do work here
          {:ok, result, state}
        end
      end
  """
  defmacro create_scheduler(opts) do
    type = Keyword.get(opts, :type, :interval)

    quote do
      case unquote(type) do
        :interval ->
          use WandererNotifier.Schedulers.IntervalScheduler,
            default_interval: unquote(Keyword.get(opts, :default_interval)),
            name: __MODULE__

        :time ->
          use WandererNotifier.Schedulers.TimeScheduler,
            default_hour: unquote(Keyword.get(opts, :default_hour)),
            default_minute: unquote(Keyword.get(opts, :default_minute)),
            hour_env_var: unquote(Keyword.get(opts, :hour_env_var)),
            minute_env_var: unquote(Keyword.get(opts, :minute_env_var)),
            name: __MODULE__

        _ ->
          raise ArgumentError, "Unknown scheduler type: #{unquote(type)}"
      end

      # Override enabled? if provided
      unquote(
        if enabled_check = Keyword.get(opts, :enabled_check) do
          quote do
            @impl true
            def enabled? do
              unquote(enabled_check).()
            end
          end
        end
      )
    end
  end
end
