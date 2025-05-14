# WandererNotifier

## Project Overview

WandererNotifier is a Discord bot application that provides notifications for important events. Built using Elixir with the Nostrum library, it offers persistent storage for tracking events and user interactions via slash commands.

## Features

- Durable storage for persisting data between restarts
- Discord slash command interface with `/notifier` command group
- Support for system and signature event notifications
- Command logging for event tracking and history
- Priority system notifications with @here mentions
- Signature tracking with custom notifications

## Technical Requirements

- Elixir with OTP
- Nostrum library for Discord integration
- Persistent storage using Erlang's term_to_binary/binary_to_term
- Supervision tree for fault tolerance
- External Map API integration for signature tracking

---

# Implementation Plan

## 1. Durable Values Store

### 1.1 Create `PersistentValues`

- **File:** `lib/wanderer_notifier/persistent_values.ex`
- **Module:** `WandererNotifier.PersistentValues`
- **Purpose:** Keep small integer lists on disk between restarts.

  defmodule WandererNotifier.PersistentValues do
  use Agent
  require Logger

      @type key  :: atom()
      @type vals :: [integer()]
      @type state :: %{key() => vals()}

      @persist_file Path.join(Application.app_dir(:wanderer_notifier, "priv"), "persistent_values.bin")

      def start_link(_opts) do
        Agent.start_link(&load_state/0, name: __MODULE__)
      end

      @spec get(key()) :: vals()
      def get(key) when is_atom(key) do
        Agent.get(__MODULE__, &Map.get(&1, key, []))
      end

      @spec put(key(), vals()) :: :ok
      def put(key, vals) when is_atom(key) and is_list(vals) do
        Agent.update(__MODULE__, fn state ->
          new_state = Map.put(state, key, vals)
          persist_state(new_state)
          new_state
        end)
      end

      defp load_state do
        case File.read(@persist_file) do
          {:ok, bin} ->
            case :erlang.binary_to_term(bin) do
              m when is_map(m) -> m
              _ -> warn_empty("corrupt data")
            end
          {:error, :enoent} ->
            %{}
          {:error, reason} ->
            warn_empty("could not read file: #{inspect(reason)}")
        end
      end

      defp persist_state(state) do
        state
        |> :erlang.term_to_binary()
        |> (&File.write!(@persist_file, &1)).()
      end

      defp warn_empty(msg) do
        Logger.warn("[PersistentValues] #{msg}, starting empty.")
        %{}
      end

  end

### 1.2 Supervision Tree

- **File:** `lib/wanderer_notifier/application.ex`
- Add `WandererNotifier.PersistentValues` before your Discord consumer:

  children = [

  # …existing…

  {Cachex, name: :my_cache},
  WandererNotifier.PersistentValues,
  WandererNotifier.Discord.Consumer,

  # …others…

  ]

### 1.3 Usage

    # read
    ids = WandererNotifier.PersistentValues.get(:my_list)

    # write
    :ok = WandererNotifier.PersistentValues.put(:my_list, [1,2,3])

---

## 2. Discord Command Listener

### 2.1 Nostrum Configuration

- **File:** `config/config.exs`

  config :nostrum,
  token: System.fetch_env!("DISCORD_TOKEN"),
  num_shards: :auto,
  gateway_intents: [
  :guilds,
  :guild_messages,
  :direct_messages,
  :message_content
  ]

> Ensure "Message Content Intent" is enabled in the Discord Developer Portal.

### 2.2 Implement Consumer

- **File:** `lib/wanderer_notifier/discord/consumer.ex`
- **Module:** `WandererNotifier.Discord.Consumer`

  defmodule WandererNotifier.Discord.Consumer do
  use Nostrum.Consumer
  alias Nostrum.Api
  alias Nostrum.Struct.Message

      @impl true
      def handle_event({:MESSAGE_CREATE, %Message{author: %{bot: true}}, _}), do: :ignore

      def handle_event({:MESSAGE_CREATE, %Message{content: content, channel_id: chan}, _}) do
        case String.split(content) do
          ["!ping"] -> Api.create_message(chan, "Pong!")
          ["!echo" | rest] -> Api.create_message(chan, Enum.join(rest, " "))
          _ -> :ignore
        end
      end

      @impl true
      def handle_event(_), do: :noop

  end

### 2.3 Slash Commands: `/notifier`

We'll register a single slash command group `notifier` with two subcommands:

1. **system**
   - **Name:** `system`
   - **Option:** `system_name` (type: string, required)
2. **sig**
   - **Name:** `sig`
   - **Option:** `signature_type` (type: string, required)

#### Command Registrar

- **File:** `lib/wanderer_notifier/discord/command_registrar.ex`

  defmodule WandererNotifier.Discord.CommandRegistrar do
  alias Nostrum.Api

      @commands [
        %{
          name: "notifier",
          description: "Notifier commands",
          options: [
            %{
              type: 1, # SUB_COMMAND
              name: "system",
              description: "Notify system event",
              options: [
                %{type: 3, name: "system_name", description: "System name", required: true}
              ]
            },
            %{
              type: 1,
              name: "sig",
              description: "Notify signature event",
              options: [
                %{type: 3, name: "signature_type", description: "Signature type", required: true}
              ]
            }
          ]
        }
      ]

      def register do
        Api.bulk_overwrite_global_application_commands(
          Application.fetch_env!(:wanderer_notifier, :application_id),
          @commands
        )
      end

  end

- Call `WandererNotifier.Discord.CommandRegistrar.register/0` in your application start.

#### Handling Interactions

In `WandererNotifier.Discord.Consumer` add:

    @impl true
    def handle_event({:INTERACTION_CREATE, interaction, _}) do
      %{data: %{name: "notifier", options: [%{name: sub, options: opts}]}} = interaction
      user_id = interaction.member.user.id
      param   = List.first(opts).value

      # persist the event
      WandererNotifier.CommandLog.log(%{type: sub, param: param, user_id: user_id})

      # respond
      Nostrum.Api.create_interaction_response(interaction, %{
        type: 4,
        data: %{content: "Logged #{sub}: #{param}"}
      })
    end

### 2.4 CommandLog

- **File:** `lib/wanderer_notifier/command_log.ex`
- **Module:** `WandererNotifier.CommandLog`
- Stores logged events to disk similarly to `PersistentValues`.

  defmodule WandererNotifier.CommandLog do
  use Agent
  require Logger

      @persist_file Path.join(Application.app_dir(:wanderer_notifier, "priv"), "command_log.bin")

      def start_link(_), do: Agent.start_link(&load/0, name: __MODULE__)

      def log(entry = %{type: _, param: _, user_id: _}) do
        Agent.update(__MODULE__, fn state ->
          new = [entry | state]
          persist(new)
          new
        end)
      end

      def all, do: Agent.get(__MODULE__, & &1)

      defp load do
        case File.read(@persist_file) do
          {:ok, bin} -> :erlang.binary_to_term(bin)
          _ -> []
        end
      end

      defp persist(state) do
        state
        |> :erlang.term_to_binary()
        |> (&File.write!(@persist_file, &1)).()
      end

  end

- Add `WandererNotifier.CommandLog` to your supervision tree.

---

## 3. Priority System Notifications

### 3.1 System Configuration

- **File:** `config/config.exs`

  config :wanderer_notifier,
  system_notifications_enabled: true,
  default_channel_id: System.fetch_env!("DISCORD_DEFAULT_CHANNEL_ID")

### 3.2 Enhanced Notification Service

- **File:** `lib/wanderer_notifier/notification_service.ex`
- **Module:** `WandererNotifier.NotificationService`

  defmodule WandererNotifier.NotificationService do
  require Logger
  alias Nostrum.Api
  alias WandererNotifier.PersistentValues

  @priority_systems_key :priority_systems

  def notify_system(system_name) do
  notifications_enabled = Application.get_env(:wanderer_notifier, :system_notifications_enabled, true)
  priority_systems = PersistentValues.get(@priority_systems_key)

      case {notifications_enabled, system_name in priority_systems} do
        {true, _} ->
          # Regular notification path
          send_system_notification(system_name, false)

        {false, true} ->
          # Override disabled notifications for priority systems with @here mention
          Logger.info("Sending priority notification for #{system_name} despite disabled notifications")
          send_system_notification(system_name, true)

        _ ->
          Logger.info("Skipping notification for #{system_name} (disabled and not priority)")
          :skip
      end

  end

  defp send_system_notification(system_name, is_priority) do
  channel_id = Application.get_env(:wanderer_notifier, :default_channel_id)

      content = if is_priority do
        "@here System notification: #{system_name} event detected!"
      else
        "System notification: #{system_name} event detected"
      end

      Api.create_message(channel_id, content)

  end

  def register_priority_system(system_name) do
  current = PersistentValues.get(@priority_systems_key)

      unless system_name in current do
        :ok = PersistentValues.put(@priority_systems_key, [system_name | current])
        Logger.info("Added #{system_name} to priority systems")
      end

  end

  def unregister_priority_system(system_name) do
  current = PersistentValues.get(@priority_systems_key)

      if system_name in current do
        :ok = PersistentValues.put(@priority_systems_key, List.delete(current, system_name))
        Logger.info("Removed #{system_name} from priority systems")
      end

  end
  end

---

## 4. Signature Tracking Integration

### 4.1 Configuration

- **File:** `config/config.exs`

  config :wanderer_notifier,
  map_api_url: System.fetch_env!("MAP_API_URL"),
  map_api_key: System.fetch_env!("MAP_API_KEY"),
  signature_channel_id: System.get_env("DISCORD_SIGNATURE_CHANNEL_ID", System.fetch_env!("DISCORD_DEFAULT_CHANNEL_ID")),
  signature_cache_ttl: 300 # 5 minutes in seconds

### 4.2 HTTP Client for Map API

- **File:** `lib/wanderer_notifier/map_api.ex`
- **Module:** `WandererNotifier.MapApi`

  defmodule WandererNotifier.MapApi do
  require Logger

  @signature_cache_key :signatures

  def fetch_signatures do
  url = "#{Application.fetch_env!(:wanderer_notifier, :map_api_url)}/signatures"
  headers = [
  {"Authorization", "Bearer #{Application.fetch_env!(:wanderer_notifier, :map_api_key)}"},
  {"Content-Type", "application/json"}
  ]

      Logger.debug("Fetching signatures from Map API")

      case HTTPoison.get(url, headers) do
        {:ok, %{status_code: 200, body: body}} ->
          signatures = Jason.decode!(body)
          Cachex.put(:my_cache, @signature_cache_key, signatures,
            ttl: :timer.seconds(Application.get_env(:wanderer_notifier, :signature_cache_ttl, 300)))
          {:ok, signatures}

        {:ok, %{status_code: status, body: body}} ->
          Logger.error("Map API error: HTTP #{status}, #{body}")
          {:error, "HTTP #{status}: #{body}"}

        {:error, %{reason: reason}} ->
          Logger.error("Map API request failed: #{inspect(reason)}")
          {:error, reason}
      end

  end

  def get\*cached_signatures do
  case Cachex.get(:my_cache, @signature_cache_key) do
  {:ok, nil} -> fetch_signatures()
  {:ok, signatures} -> {:ok, signatures}

  - -> {:error, "Cache error"}
    end
    end
    end

### 4.3 Signature Notification Service

- **File:** `lib/wanderer_notifier/signature_service.ex`
- **Module:** `WandererNotifier.SignatureService`

  defmodule WandererNotifier.SignatureService do
  require Logger
  alias Nostrum.Api
  alias WandererNotifier.{PersistentValues, MapApi}

  @tracked_signatures_key :tracked_signatures

  def check_and_notify_signatures do
  with {:ok, signatures} <- MapApi.get_cached_signatures(),
  tracked <- PersistentValues.get(@tracked_signatures_key) do

        # Find signatures that are being tracked
        notifications =
          signatures
          |> Enum.filter(fn sig -> sig["type"] in tracked end)
          |> Enum.map(&format_signature_notification/1)

        # Send notifications if any
        unless Enum.empty?(notifications) do
          channel_id = Application.get_env(:wanderer_notifier, :signature_channel_id)

          for notification <- notifications do
            Api.create_message(channel_id, notification)
          end
        end

        {:ok, length(notifications)}
      else
        error -> error
      end

  end

  def track_signature(signature_type) do
  current = PersistentValues.get(@tracked_signatures_key)

      unless signature_type in current do
        :ok = PersistentValues.put(@tracked_signatures_key, [signature_type | current])
        Logger.info("Now tracking signature type: #{signature_type}")
      end

  end

  def untrack_signature(signature_type) do
  current = PersistentValues.get(@tracked_signatures_key)

      if signature_type in current do
        :ok = PersistentValues.put(@tracked_signatures_key, List.delete(current, signature_type))
        Logger.info("Stopped tracking signature type: #{signature_type}")
      end

  end

  defp format_signature_notification(signature) do
  """
  **New Signature Detected**
  Type: #{signature["type"]}
  System: #{signature["system"]}
  ID: #{signature["id"]}
  Added: #{format_timestamp(signature["timestamp"])}
  """
  end

  defp format*timestamp(nil), do: "Unknown"
  defp format_timestamp(timestamp) do
  case DateTime.from_iso8601(timestamp) do
  {:ok, datetime, *} -> Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
  \_ -> timestamp
  end
  end
  end

### 4.4 Schedule Regular Signature Checks

- **File:** `lib/wanderer_notifier/application.ex`
- Add periodic worker to check for signatures:

  defmodule WandererNotifier.SignatureChecker do
  use GenServer
  require Logger
  alias WandererNotifier.SignatureService

  @check_interval :timer.minutes(5)

  def start*link(*) do
  GenServer.start_link(**MODULE**, %{})
  end

  @impl true
  def init(state) do
  schedule_check()
  {:ok, state}
  end

  @impl true
  def handle_info(:check_signatures, state) do
  case SignatureService.check_and_notify_signatures() do
  {:ok, count} ->
  Logger.info("Signature check complete. Sent #{count} notifications.")
  {:error, reason} ->
  Logger.error("Signature check failed: #{inspect(reason)}")
  end

      schedule_check()
      {:noreply, state}

  end

  defp schedule_check do
  Process.send_after(self(), :check_signatures, @check_interval)
  end
  end

- Add to supervision tree:

  children = [

  # …existing…

  {Cachex, name: :my_cache},
  WandererNotifier.PersistentValues,
  WandererNotifier.CommandLog,
  WandererNotifier.SignatureChecker,
  WandererNotifier.Discord.Consumer,

  # …others…

  ]

---

## 5. Testing & Documentation

- **Unit tests** for `PersistentValues` and `CommandLog` (round-trip, default state)
- **Integration**: Simulate `INTERACTION_CREATE` to assert logging + response
- **MapApi**: Test signature fetching with mocked HTTP responses
- **README**: Document slash command registration, usage, and where logs live

---

## 6. Timeline

| Task                                     | Estimate     |
| ---------------------------------------- | ------------ |
| PersistentValues + CommandLog            | 45 min       |
| Slash command registrar + consumer logic | 45 min       |
| Priority system notifications            | 30 min       |
| Map API integration                      | 60 min       |
| Signature tracking service               | 45 min       |
| Tests & docs                             | 45 min       |
| **Total**                                | **~4.5 hrs** |
