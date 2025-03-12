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

# Define mocks for dependency injection
Mox.defmock(WandererNotifier.LicenseManager.ClientMock, for: WandererNotifier.LicenseManager.Client)
Mox.defmock(WandererNotifier.LicenseMock, for: WandererNotifier.License)
Mox.defmock(WandererNotifier.Discord.NotifierMock, for: WandererNotifier.Discord.Notifier)

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
Application.put_env(:wanderer_notifier, :discord_notifier, WandererNotifier.Discord.NotifierMock)
Application.put_env(:wanderer_notifier, :license_manager_client, WandererNotifier.LicenseManager.ClientMock)

# Set up default stubs for mocks
Mox.stub_with(WandererNotifier.LicenseMock, WandererNotifier.LicenseStub)
