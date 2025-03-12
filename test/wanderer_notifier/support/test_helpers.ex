defmodule WandererNotifier.TestHelpers do
  @moduledoc """
  Helper functions for testing.
  """

  @doc """
  Sets up the license manager mock with a specific response.

  ## Parameters

  - `response`: The response to return from the validate_license function.
  """
  def setup_license_mock(response) do
    Mox.stub(WandererNotifier.LicenseManager.ClientMock, :validate_license, fn _ -> response end)
  end

  @doc """
  Sets up environment variables for testing.

  ## Parameters

  - `vars`: A map of environment variables to set.
  """
  def setup_env_vars(vars) do
    Enum.each(vars, fn {key, value} ->
      Application.put_env(:wanderer_notifier, key, value)
    end)
  end

  @doc """
  Creates a valid license response.

  ## Parameters

  - `features`: A list of enabled features.
  - `tier`: The license tier (default: "premium").
  """
  def valid_license_response(features \\ ["feature1", "feature2"], tier \\ "premium") do
    {:ok, %{
      "valid" => true,
      "features" => features,
      "tier" => tier,
      "expires_at" => "2099-12-31T23:59:59Z"
    }}
  end

  @doc """
  Creates an invalid license response with a specific error.

  ## Parameters

  - `error`: The error reason.
  """
  def invalid_license_response(error \\ :license_not_found) do
    {:error, error}
  end
end
