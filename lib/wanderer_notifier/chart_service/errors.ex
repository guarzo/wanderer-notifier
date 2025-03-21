defmodule WandererNotifier.ChartService.Errors do
  @moduledoc """
  Defines structured error types for the chart service.

  This module provides standardized error types and helper functions for
  the chart service, improving error handling and reporting.
  """

  # Define error modules
  defmodule ConfigurationError do
    @moduledoc """
    Error returned when chart configuration is invalid.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            details: any()
          }
    defexception [:message, :details]

    @impl true
    def message(%__MODULE__{message: message, details: details}) do
      "Chart configuration error: #{message}, details: #{inspect(details)}"
    end
  end

  defmodule DataError do
    @moduledoc """
    Error returned when chart data is missing or invalid.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            details: any()
          }
    defexception [:message, :details]

    @impl true
    def message(%__MODULE__{message: message, details: details}) do
      "Chart data error: #{message}, details: #{inspect(details)}"
    end
  end

  defmodule RenderingError do
    @moduledoc """
    Error returned when chart rendering fails.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            details: any()
          }
    defexception [:message, :details]

    @impl true
    def message(%__MODULE__{message: message, details: details}) do
      "Chart rendering error: #{message}, details: #{inspect(details)}"
    end
  end

  defmodule ServiceError do
    @moduledoc """
    Error returned when external chart service is unavailable.
    """
    @type t :: %__MODULE__{
            message: String.t(),
            details: any()
          }
    defexception [:message, :details]

    @impl true
    def message(%__MODULE__{message: message, details: details}) do
      "Chart service error: #{message}, details: #{inspect(details)}"
    end
  end

  @doc """
  Converts an error tuple to a structured error exception.

  ## Parameters
    - {:error, reason} - An error tuple
    - error_type - The type of error to create, defaults to ConfigurationError

  ## Returns
    - An exception struct of the specified type
  """
  def to_exception({:error, reason}, error_type \\ nil) do
    # Determine which error type to use
    module = determine_error_module(error_type)

    # Format the message based on reason type
    message = format_reason_message(reason)

    # Create the exception struct
    struct(module, %{message: message, details: reason})
  end

  # Determine which error module to use based on the error_type
  defp determine_error_module(nil), do: ConfigurationError
  defp determine_error_module(ConfigurationError), do: ConfigurationError
  defp determine_error_module(DataError), do: DataError
  defp determine_error_module(RenderingError), do: RenderingError
  defp determine_error_module(ServiceError), do: ServiceError
  defp determine_error_module(_), do: ConfigurationError

  # Format the error message based on the reason type
  defp format_reason_message(reason) when is_binary(reason), do: reason
  defp format_reason_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason_message(_), do: "Unknown error"

  @doc """
  Formats an error response suitable for API responses.

  ## Parameters
    - {:error, reason} - An error tuple
    - context - Additional context for the error

  ## Returns
    - A map with error details
  """
  def format_response({:error, reason}, context \\ nil) do
    %{
      status: "error",
      message: format_error_message(reason),
      details: inspect(reason),
      context: context
    }
  end

  # Private helpers

  defp format_error_message(reason) when is_binary(reason), do: reason
  defp format_error_message(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error_message(_), do: "An error occurred while processing the chart request"
end
