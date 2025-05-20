defmodule Credo.Check.Warning.CacheKeyStringLiteral do
  @moduledoc """
  A check that warns about string literals that look like cache keys.

  Cache keys should be generated using the `WandererNotifier.Cache.Keys` helpers
  instead of being written as string literals.

  Example:

      # Bad
      Redis.get("map:system:12345")

      # Good
      key = CacheKeys.system(12345)
      Redis.get(key)
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check:
        "Cache keys should be generated using the WandererNotifier.Cache.Keys helpers instead of being written as string literals. Example: Redis.get(\"map:system:12345\") is bad, use key = CacheKeys.system(12345); Redis.get(key) instead.",
      params: []
    ]

  @cache_key_pattern ~r/"(?:map|zkill|system|character|killmail):(?:[a-z_]+)(?::[a-z0-9_]+)*"/

  @impl true
  def run(source_file, _params \\ []) do
    source_file
    |> Credo.Code.to_tokens()
    |> Enum.reduce([], &check_token/2)
  end

  defp check_token({:string_literal, {line_no, column, _}, string}, issues) do
    if String.match?(string, @cache_key_pattern) do
      [
        format_issue(
          "Found cache key string literal. Use WandererNotifier.Cache.Keys helpers instead.",
          line_no,
          column,
          string
        )
        | issues
      ]
    else
      issues
    end
  end

  defp check_token(_, issues), do: issues

  defp format_issue(message, line_no, column, trigger) do
    %{
      message: message,
      line_no: line_no,
      column: column,
      trigger: trigger
    }
  end
end
