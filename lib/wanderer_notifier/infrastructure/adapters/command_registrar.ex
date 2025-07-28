defmodule WandererNotifier.Infrastructure.Adapters.Discord.CommandRegistrar do
  @moduledoc """
  Handles registration of Discord slash commands for the WandererNotifier bot.

  This module manages the registration and updating of the `/notifier` command group
  with Discord's API. Commands are registered globally and include:

  - `/notifier system <system_name>` - Register for system notifications
  - `/notifier sig <signature_type>` - Register for signature notifications

  The commands are automatically registered when the application starts up.
  """

  require Logger
  alias Nostrum.Api.ApplicationCommand
  alias WandererNotifier.Shared.Config

  @doc """
  The main command definition for the `/notifier` command group.
  """
  def commands do
    [
      %{
        name: "notifier",
        description: "WandererNotifier configuration and tracking commands",
        options: [
          %{
            type: 1,
            # SUB_COMMAND
            name: "system",
            description: "Configure system notifications and priority tracking",
            options: [
              %{
                type: 3,
                # STRING
                name: "system_name",
                description: "Name of the EVE system to track (e.g., 'Jita', 'Amarr')",
                required: true
              },
              %{
                type: 3,
                # STRING
                name: "action",
                description: "Action to perform",
                required: false,
                choices: [
                  %{name: "add-priority", value: "add_priority"},
                  %{name: "remove-priority", value: "remove_priority"},
                  %{name: "track", value: "track"},
                  %{name: "untrack", value: "untrack"}
                ]
              }
            ]
          },
          %{
            type: 1,
            # SUB_COMMAND
            name: "status",
            description: "Show current tracking status and configuration",
            options: []
          }
        ]
      }
    ]
  end

  @doc """
  Registers all slash commands with Discord.

  This function should be called during application startup to ensure
  commands are available to users.
  """
  @spec register() :: :ok | {:error, term()}
  def register do
    application_id = get_application_id()

    if application_id do
      register_commands_with_retry(application_id)
    else
      {:error, :missing_application_id}
    end
  end

  # Registers commands with retry logic to handle rate limiting.
  defp register_commands_with_retry(application_id, retries \\ 3) do
    case ApplicationCommand.bulk_overwrite_global_commands(application_id, commands()) do
      {:ok, _commands} -> handle_registration_success()
      {:error, error} -> handle_registration_error(error, application_id, retries)
    end
  end

  defp handle_registration_success do
    Logger.info("Successfully registered Discord slash commands")
    log_registered_commands()
    :ok
  end

  defp handle_registration_error(%{status_code: 429} = error, application_id, retries)
       when retries > 0 do
    handle_rate_limit_error(error, application_id, retries)
  end

  defp handle_registration_error(%{status_code: status} = error, application_id, retries)
       when status in [500, 502, 503, 504] and retries > 0 do
    handle_server_error(error, status, application_id, retries)
  end

  defp handle_registration_error(%{status_code: 401}, _application_id, _retries) do
    Logger.error("Invalid Discord bot token for command registration")
    {:error, :invalid_token}
  end

  defp handle_registration_error(%{status_code: 403}, _application_id, _retries) do
    Logger.error("Bot lacks permissions to register commands")

    {:error, :insufficient_permissions}
  end

  defp handle_registration_error(error, application_id, _retries) do
    Logger.error("Failed to register Discord commands",
      category: :kill,
      application_id: application_id
    )

    {:error, error}
  end

  defp handle_rate_limit_error(error, application_id, retries) do
    wait_time = extract_retry_after(error)

    Logger.warning(
      "Rate limited registering commands, retrying in #{wait_time}ms",
      category: :api
    )

    Process.sleep(wait_time)
    register_commands_with_retry(application_id, retries - 1)
  end

  defp handle_server_error(_error, status, application_id, retries) do
    attempt = 3 - retries + 1
    wait_time = calculate_exponential_backoff(attempt)

    Logger.warning(
      "Server error registering commands (#{status}, [], retrying in #{wait_time}ms",
      attempt: attempt,
      retries_left: retries - 1
    )

    Process.sleep(wait_time)
    register_commands_with_retry(application_id, retries - 1)
  end

  @doc """
  Removes all registered slash commands.

  Useful for cleanup or testing purposes.
  """
  @spec unregister() :: :ok | {:error, term()}
  def unregister do
    application_id = get_application_id()

    if application_id do
      case ApplicationCommand.bulk_overwrite_global_commands(application_id, []) do
        {:ok, _} ->
          Logger.info("Successfully unregistered all Discord slash commands")

          :ok

        {:error, error} ->
          Logger.error("Failed to unregister Discord commands", error: inspect(error))

          {:error, error}
      end
    else
      {:error, :missing_application_id}
    end
  end

  @doc """
  Lists currently registered commands from Discord.

  Useful for debugging and verification.
  """
  @spec list_registered_commands() :: {:ok, list()} | {:error, term()}
  def list_registered_commands do
    application_id = get_application_id()

    if application_id do
      case ApplicationCommand.global_commands(application_id) do
        {:ok, commands} ->
          Logger.info("Retrieved #{length(commands)} registered commands")

          {:ok, commands}

        {:error, error} ->
          Logger.error("Failed to list registered commands",
            category: :kill,
            error: inspect(error)
          )

          {:error, error}
      end
    else
      {:error, :missing_application_id}
    end
  end

  @doc """
  Validates that a command interaction matches our expected structure.
  """
  @spec valid_interaction?(map()) :: boolean()
  def valid_interaction?(%{data: %{name: "notifier", options: options}}) when is_list(options) do
    case options do
      [%{name: subcommand}] when subcommand in ["system", "status"] -> true
      _ -> false
    end
  end

  def valid_interaction?(_), do: false

  @doc """
  Extracts command details from a Discord interaction.

  Returns a normalized map with command information.
  """
  @spec extract_command_details(map()) :: {:ok, map()} | {:error, :invalid_interaction}
  def extract_command_details(interaction) do
    if valid_interaction?(interaction) do
      %{data: %{options: [subcommand]}} = interaction

      details = %{
        type: subcommand.name,
        options: extract_options(subcommand),
        user_id: get_user_id(interaction),
        username: get_username(interaction),
        guild_id: Map.get(interaction, :guild_id),
        channel_id: Map.get(interaction, :channel_id),
        interaction_id: interaction.id,
        interaction_token: interaction.token
      }

      {:ok, details}
    else
      {:error, :invalid_interaction}
    end
  end

  # Private Helper Functions

  # Gets the Discord application ID from configuration
  defp get_application_id do
    try do
      case Config.discord_application_id() do
        nil ->
          nil

        id when is_binary(id) ->
          case Integer.parse(id) do
            {int_id, ""} -> int_id
            _ -> nil
          end

        id when is_integer(id) ->
          id
      end
    rescue
      _ -> nil
    end
  end

  # Extracts retry-after header from rate limit response
  defp extract_retry_after(%{response: response}) when is_map(response) do
    # Try to get retry-after from the response structure
    case Map.get(response, :retry_after) do
      retry_after when is_integer(retry_after) -> retry_after * 1000
      # Default to 5 seconds
      _ -> 5000
    end
  end

  # Default to 5 seconds
  defp extract_retry_after(_), do: 5000

  defp calculate_exponential_backoff(attempt) do
    # Exponential backoff: 1s, 2s, 4s, max 8s
    base_ms = 1000
    max_ms = 8000

    backoff = base_ms * :math.pow(2, attempt - 1)
    # Add 10-20% jitter
    with_jitter = backoff * (0.9 + :rand.uniform() * 0.2)

    min(trunc(with_jitter), max_ms)
  end

  # Logs details about registered commands
  defp log_registered_commands do
    commands()
    |> Enum.each(fn command ->
      subcommands = Enum.map(command.options, & &1.name)

      Logger.info("Registered command: /#{command.name}",
        subcommands: subcommands,
        category: :discord
      )
    end)
  end

  # Extracts options from a subcommand
  defp extract_options(%{options: options}) when is_list(options) do
    Map.new(options, fn %{name: name, value: value} -> {name, value} end)
  end

  defp extract_options(_), do: %{}

  # Gets user ID from interaction
  defp get_user_id(%{member: %{user: %{id: user_id}}}), do: user_id
  defp get_user_id(%{user: %{id: user_id}}), do: user_id
  defp get_user_id(_), do: nil

  # Gets username from interaction
  defp get_username(%{member: %{user: %{username: username}}}), do: username
  defp get_username(%{user: %{username: username}}), do: username
  defp get_username(_), do: nil
end
