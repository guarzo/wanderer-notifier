defmodule WandererNotifier.Shared.Env do
  @moduledoc """
  Consolidated environment variable handling for the application.

  This module centralizes all environment variable access with consistent
  validation, type conversion, and error handling. All modules should use
  this module instead of direct System.get_env/Application.get_env calls.
  """

  @doc """
  Gets an environment variable with a default value.
  Returns the raw string value or the default if not set.
  """
  @spec get(String.t(), term()) :: String.t() | term()
  def get(key, default \\ nil) when is_binary(key) do
    System.get_env(key, default)
  end

  @doc """
  Gets a required environment variable.
  Raises an error if the variable is missing or empty.
  """
  @spec get_required(String.t()) :: String.t()
  def get_required(key) when is_binary(key) do
    case System.get_env(key) do
      nil -> raise "Missing required environment variable: #{key}"
      "" -> raise "Empty required environment variable: #{key}"
      value -> value
    end
  end

  @doc """
  Gets an environment variable as a boolean.
  Converts common boolean representations to true/false.

  ## Examples
      iex> System.put_env("TEST_BOOL", "true")
      iex> WandererNotifier.Shared.Env.get_boolean("TEST_BOOL", false)
      true
      
      iex> WandererNotifier.Shared.Env.get_boolean("MISSING_BOOL", false)
      false
  """
  @spec get_boolean(String.t(), boolean()) :: boolean()
  def get_boolean(key, default) when is_binary(key) and is_boolean(default) do
    case System.get_env(key) do
      nil -> default
      value -> parse_boolean_value(value, default)
    end
  end

  defp parse_boolean_value(value, default) do
    case String.downcase(value) do
      v when v in ["true", "1", "yes", "on"] -> true
      v when v in ["false", "0", "no", "off"] -> false
      _ -> default
    end
  end

  @doc """
  Gets an environment variable as an integer.
  Returns the default if the variable is missing or cannot be parsed.

  ## Examples
      iex> System.put_env("TEST_PORT", "4000")
      iex> WandererNotifier.Shared.Env.get_integer("TEST_PORT", 3000)
      4000
      
      iex> WandererNotifier.Shared.Env.get_integer("MISSING_PORT", 3000)
      3000
  """
  @spec get_integer(String.t(), integer()) :: integer()
  def get_integer(key, default) when is_binary(key) and is_integer(default) do
    case System.get_env(key) do
      nil ->
        default

      value ->
        case Integer.parse(value, 10) do
          {int, ""} -> int
          _ -> default
        end
    end
  end

  @doc """
  Gets an environment variable as a float.
  Returns the default if the variable is missing or cannot be parsed.
  """
  @spec get_float(String.t(), float()) :: float()
  def get_float(key, default) when is_binary(key) and is_number(default) do
    case System.get_env(key) do
      nil ->
        default

      value ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> default
        end
    end
  end

  @doc """
  Gets an environment variable as an atom.
  Returns the default if the variable is missing or cannot be converted.

  WARNING: This function uses String.to_existing_atom/1 to prevent atom exhaustion.
  The atom must already exist in the system. Only use this function with trusted
  environment variables that map to known, predefined atoms.

  ## Examples
      iex> System.put_env("LOG_LEVEL", "info")
      iex> WandererNotifier.Shared.Env.get_atom("LOG_LEVEL", :debug)
      :info
      
      iex> System.put_env("INVALID_ATOM", "non_existing_atom")
      iex> WandererNotifier.Shared.Env.get_atom("INVALID_ATOM", :default)
      :default
  """
  @spec get_atom(String.t(), atom()) :: atom()
  def get_atom(key, default) when is_binary(key) and is_atom(default) do
    case System.get_env(key) do
      nil ->
        default

      value ->
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError -> default
        end
    end
  end

  @doc """
  Gets an environment variable as a list of strings, split by a delimiter.
  Returns the default if the variable is missing.

  ## Examples
      iex> System.put_env("TEST_LIST", "item1,item2,item3")
      iex> WandererNotifier.Shared.Env.get_list("TEST_LIST", [])
      ["item1", "item2", "item3"]
  """
  @spec get_list(String.t(), [String.t()], String.t()) :: [String.t()]
  def get_list(key, default \\ [], delimiter \\ ",") when is_binary(key) and is_list(default) do
    case System.get_env(key) do
      nil ->
        default

      "" ->
        default

      value ->
        value
        |> String.split(delimiter)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  @doc """
  Checks if an environment variable is present and non-empty.
  """
  @spec present?(String.t()) :: boolean()
  def present?(key) when is_binary(key) do
    case System.get_env(key) do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  @doc """
  Gets an application configuration value with environment variable override.
  Checks environment variable first, then falls back to application config.

  ## Examples
      # If ENV_VAR is set, use it; otherwise use app config
      get_app_config(:wanderer_notifier, :some_key, "ENV_VAR", "default")
  """
  @spec get_app_config(atom(), atom(), String.t(), term()) :: term()
  def get_app_config(app, key, env_var, default)
      when is_atom(app) and is_atom(key) and is_binary(env_var) do
    case System.get_env(env_var) do
      nil -> Application.get_env(app, key, default)
      value -> value
    end
  end

  @doc """
  Returns a map of all environment variables that match a prefix.
  Useful for gathering related configuration values.

  ## Examples
      iex> WandererNotifier.Shared.Env.get_prefixed("DISCORD_")
      %{"DISCORD_BOT_TOKEN" => "...", "DISCORD_CHANNEL_ID" => "..."}
  """
  @spec get_prefixed(String.t()) :: %{String.t() => String.t()}
  def get_prefixed(prefix) when is_binary(prefix) do
    System.get_env()
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, prefix) end)
    |> Enum.into(%{})
  end

  @doc """
  Logs environment variables for debugging purposes.
  Automatically redacts sensitive values based on common patterns.
  """
  @spec log_variables([String.t()], String.t()) :: :ok
  def log_variables(keys, context \\ "Environment variables") when is_list(keys) do
    require Logger

    Logger.debug("#{context}:")

    sensitive_patterns = [
      "_TOKEN",
      "_KEY",
      "_SECRET",
      "_PASSWORD",
      "_SALT"
    ]

    Enum.each(keys, fn key ->
      log_single_variable(key, sensitive_patterns)
    end)

    :ok
  end

  defp log_single_variable(key, sensitive_patterns) do
    require Logger

    case System.get_env(key) do
      nil ->
        Logger.debug("  #{key}: (not set)")

      value ->
        is_sensitive = Enum.any?(sensitive_patterns, &String.contains?(key, &1))
        safe_value = if is_sensitive, do: "[REDACTED]", else: value
        Logger.debug("  #{key}: #{safe_value}")
    end
  end

  @doc """
  Validates that all required environment variables are present.
  Returns :ok or {:error, missing_keys}.
  """
  @spec validate_required([String.t()]) :: :ok | {:error, [String.t()]}
  def validate_required(keys) when is_list(keys) do
    missing_keys =
      keys
      |> Enum.reject(&present?/1)

    case missing_keys do
      [] -> :ok
      missing -> {:error, missing}
    end
  end
end
