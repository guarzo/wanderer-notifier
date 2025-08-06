defmodule WandererNotifier.Domains.License.Errors do
  @moduledoc """
  Domain-specific error types for the License domain.

  Provides consistent error handling and formatting for license validation,
  feature access control, and license management operations.
  """

  @doc """
  Creates a license validation error.

  ## Examples
      
      iex> license_error(:invalid_key)
      {:error, {:license, :invalid_key}}
      
      iex> license_error(:rate_limited, "Too many requests")
      {:error, {:license, {:rate_limited, "Too many requests"}}}
  """
  def license_error(reason) when is_atom(reason) do
    {:error, {:license, reason}}
  end

  def license_error(reason, context) do
    {:error, {:license, {reason, context}}}
  end

  @doc """
  Creates a feature access error.
  """
  def feature_error(reason) when is_atom(reason) do
    {:error, {:feature, reason}}
  end

  def feature_error(reason, context) do
    {:error, {:feature, {reason, context}}}
  end

  @doc """
  Creates a validation API error.
  """
  def api_error(reason) when is_atom(reason) do
    {:error, {:license_api, reason}}
  end

  def api_error(reason, context) do
    {:error, {:license_api, {reason, context}}}
  end

  @doc """
  Formats license domain errors into user-friendly messages.

  ## Examples

      iex> format_error({:license, :invalid_key})
      "Invalid license key"
      
      iex> format_error({:feature, :not_available})
      "Feature not available with current license"
  """
  def format_error({:license, :invalid_key}), do: "Invalid license key"
  def format_error({:license, :expired}), do: "License has expired"
  def format_error({:license, :not_found}), do: "License not found"
  def format_error({:license, :rate_limited}), do: "License validation rate limited"
  def format_error({:license, :validation_failed}), do: "License validation failed"
  def format_error({:license, :bot_not_assigned}), do: "Bot not assigned to this license"
  def format_error({:license, :invalid_license}), do: "Invalid license"
  def format_error({:license, :timeout}), do: "License validation timed out"
  def format_error({:license, reason}), do: "License error: #{inspect(reason)}"

  def format_error({:feature, :not_available}), do: "Feature not available with current license"
  def format_error({:feature, :disabled}), do: "Feature is disabled"
  def format_error({:feature, :limit_exceeded}), do: "Feature usage limit exceeded"
  def format_error({:feature, reason}), do: "Feature access error: #{inspect(reason)}"

  def format_error({:license_api, :unavailable}), do: "License validation service unavailable"
  def format_error({:license_api, :invalid_response}), do: "Invalid response from license service"
  def format_error({:license_api, :network_error}), do: "Network error contacting license service"
  def format_error({:license_api, reason}), do: "License API error: #{inspect(reason)}"

  def format_error(reason), do: "Unknown license domain error: #{inspect(reason)}"

  @doc """
  Checks if an error is from the license domain.
  """
  def license_error?({:error, {:license, _}}), do: true
  def license_error?({:error, {:feature, _}}), do: true
  def license_error?({:error, {:license_api, _}}), do: true
  def license_error?(_), do: false

  @doc """
  Extracts the error reason from a license domain error.
  """
  def extract_reason({:error, {:license, reason}}), do: reason
  def extract_reason({:error, {:feature, reason}}), do: reason
  def extract_reason({:error, {:license_api, reason}}), do: reason
  def extract_reason({:error, reason}), do: reason

  @doc """
  Maps license errors to HTTP status codes for web responses.
  """
  def to_http_status({:license, :invalid_key}), do: 400
  def to_http_status({:license, :not_found}), do: 404
  # Payment required
  def to_http_status({:license, :expired}), do: 402
  def to_http_status({:license, :rate_limited}), do: 429
  def to_http_status({:license, :timeout}), do: 408
  def to_http_status({:feature, :not_available}), do: 403
  def to_http_status({:feature, :limit_exceeded}), do: 429
  def to_http_status({:license_api, :unavailable}), do: 503
  def to_http_status(_), do: 500
end
