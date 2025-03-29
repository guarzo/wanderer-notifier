defmodule WandererNotifier.Config.License do
  @moduledoc """
  Configuration module for license-related settings.
  """

  @doc """
  Gets the license key from configuration.
  """
  def get_license_key do
    Application.get_env(:wanderer_notifier, :license_key)
  end

  @doc """
  Gets the license manager URL from configuration.
  """
  def get_license_manager_url do
    Application.get_env(:wanderer_notifier, :license_manager_url)
  end

  @doc """
  Gets the current license status.
  """
  def status do
    %{
      valid: valid?(),
      bot_assigned: bot_assigned?()
    }
  end

  defp valid? do
    get_license_key() != nil
  end

  defp bot_assigned? do
    get_license_manager_url() != nil
  end
end
