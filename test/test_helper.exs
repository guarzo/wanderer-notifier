ExUnit.start()

# Define the LicenseStub module
defmodule WandererNotifier.LicenseStub do
  @behaviour WandererNotifier.License

  @impl true
  def validate do
    true
  end

  @impl true
  def status do
    %{valid: true}
  end
end

# Define a NotifierStub module
defmodule WandererNotifier.NotifierStub do
  @behaviour WandererNotifier.NotifierBehaviour

  @impl true
  def send_message(message) do
    IO.puts("TEST NOTIFIER: #{message}")
    :ok
  end

  @impl true
  def send_embed(title, description, _url, _color) do
    IO.puts("TEST EMBED: #{title} - #{description}")
    :ok
  end

  @impl true
  def send_enriched_kill_embed(_enriched_kill, kill_id) do
    IO.puts("TEST KILL EMBED: Kill ID #{kill_id}")
    :ok
  end

  @impl true
  def send_new_tracked_character_notification(character) do
    character_id = Map.get(character, "character_id") || Map.get(character, "eve_id")
    IO.puts("TEST CHARACTER NOTIFICATION: Character ID #{character_id}")
    :ok
  end

  @impl true
  def send_new_system_notification(system) do
    system_id = Map.get(system, "system_id") || Map.get(system, :system_id)
    IO.puts("TEST SYSTEM NOTIFICATION: System ID #{system_id}")
    :ok
  end
end

# Define mocks for dependency injection
Mox.defmock(WandererNotifier.LicenseManager.ClientMock, for: WandererNotifier.LicenseManager.Client)
Mox.defmock(WandererNotifier.LicenseMock, for: WandererNotifier.License)
Mox.defmock(WandererNotifier.NotifierMock, for: WandererNotifier.NotifierBehaviour)

# Set up test environment
Application.put_env(:wanderer_notifier, :license_key, "test_license_key")
Application.put_env(:wanderer_notifier, :license_manager_api_url, "https://test.license.manager")
Application.put_env(:wanderer_notifier, :bot_registration_token, "test_bot_token")
Application.put_env(:wanderer_notifier, :bot_type, "notifier")

# Discord configuration
Application.put_env(:wanderer_notifier, :discord, %{
  channel_id: "test_channel_id",
  bot_token: "test_bot_token"
})

# Set up mocks for dependency injection
Application.put_env(:wanderer_notifier, :license_client, WandererNotifier.LicenseMock)
Application.put_env(:wanderer_notifier, :notifier, WandererNotifier.NotifierMock)
Application.put_env(:wanderer_notifier, :license_manager_client, WandererNotifier.LicenseManager.ClientMock)

# Set up default stubs for mocks
Mox.stub_with(WandererNotifier.LicenseMock, WandererNotifier.LicenseStub)
Mox.stub_with(WandererNotifier.NotifierMock, WandererNotifier.NotifierStub)
