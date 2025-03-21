ExUnit.start()

# Start required applications for testing
Application.ensure_all_started(:hackney)
Application.ensure_all_started(:mox)

# Define mocks for testing
Mox.defmock(WandererNotifier.MockHTTPClient, for: WandererNotifier.Api.Http.ClientBehaviour)
Mox.defmock(WandererNotifier.MockDiscordAPI, for: WandererNotifier.Discord.ApiBehaviour)
Mox.defmock(WandererNotifier.MockESIService, for: WandererNotifier.Api.ESI.ServiceBehaviour)

# Set up application environment for testing
Application.put_env(:wanderer_notifier, :env, :test)
Application.put_env(:wanderer_notifier, :http_client, WandererNotifier.MockHTTPClient)
Application.put_env(:wanderer_notifier, :discord_api, WandererNotifier.MockDiscordAPI)
Application.put_env(:wanderer_notifier, :esi_service, WandererNotifier.MockESIService)

# Prevent application from starting for tests by default
Application.put_env(:ex_unit, :autorun, false)
