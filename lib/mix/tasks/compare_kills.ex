defmodule Mix.Tasks.CompareKills do
  @moduledoc """
  Mix task to compare killmails between our database and zKillboard.

  ## Usage

      mix compare_kills CHARACTER_ID [--start START_DATE] [--end END_DATE]

  Where:
    * CHARACTER_ID is the EVE character ID to compare
    * START_DATE is optional, format: "YYYY-MM-DD", defaults to 7 days ago
    * END_DATE is optional, format: "YYYY-MM-DD", defaults to today

  ## Examples

      mix compare_kills 123456
      mix compare_kills 123456 --start 2024-01-01 --end 2024-01-31
  """

  use Mix.Task
  alias WandererNotifier.Services.KillmailComparison

  @shortdoc "Compare killmails with zKillboard"
  def run(args) do
    # Start required applications
    Application.ensure_all_started(:wanderer_notifier)

    # Parse arguments
    {opts, [character_id_str | _], _} =
      OptionParser.parse(args,
        strict: [start: :string, end: :string],
        aliases: [s: :start, e: :end]
      )

    # Convert character_id to integer
    character_id = String.to_integer(character_id_str)

    # Get date range
    end_date = parse_date(opts[:end], Date.utc_today())
    start_date = parse_date(opts[:start], Date.add(end_date, -7))

    # Convert dates to DateTime for start and end of day
    start_datetime = DateTime.new!(start_date, ~T[00:00:00.000], "Etc/UTC")
    end_datetime = DateTime.new!(end_date, ~T[23:59:59.999], "Etc/UTC")

    # Run comparison
    case KillmailComparison.compare_killmails(character_id, start_datetime, end_datetime) do
      {:ok, results} ->
        print_results(results, character_id, start_date, end_date)

        # If there are missing kills, analyze them
        if length(results.missing_kills) > 0 do
          analyze_missing_kills(character_id, results.missing_kills)
        end

      {:error, error} ->
        Mix.shell().error("Error comparing kills: #{inspect(error)}")
    end
  end

  defp parse_date(nil, default), do: default

  defp parse_date(date_str, _default) do
    Date.from_iso8601!(date_str)
  end

  defp print_results(results, character_id, start_date, end_date) do
    Mix.shell().info("""

    Kill Comparison Results for Character #{character_id}
    Time Period: #{Date.to_string(start_date)} to #{Date.to_string(end_date)}
    ================================================
    Our Database Kills:     #{results.our_kills}
    zKillboard Kills:       #{results.zkill_kills}
    Missing Kills:          #{length(results.missing_kills)}
    Extra Kills:            #{length(results.extra_kills)}

    Analysis:
    ---------
    Match Percentage: #{results.comparison.percentage_match}%
    #{results.comparison.analysis}
    """)

    if length(results.missing_kills) > 0 do
      Mix.shell().info("""

      Missing Kill IDs:
      #{Enum.join(results.missing_kills, ", ")}
      """)
    end

    if length(results.extra_kills) > 0 do
      Mix.shell().info("""

      Extra Kill IDs:
      #{Enum.join(results.extra_kills, ", ")}
      """)
    end
  end

  defp analyze_missing_kills(character_id, kill_ids) do
    Mix.shell().info("\nAnalyzing missing kills...")

    # Since analyze_missing_kills always returns {:ok, _}, we can simplify this
    {:ok, analysis} = KillmailComparison.analyze_missing_kills(character_id, kill_ids)
    print_analysis_results(analysis)
  end

  defp print_analysis_results(analysis) do
    Mix.shell().info("\nMissing Kills Analysis:")
    Mix.shell().info("=======================")

    Enum.each(analysis, fn {reason, kills} ->
      kill_count = length(kills)
      reason_str = format_reason(reason)

      Mix.shell().info("#{reason_str}: #{kill_count} kills")

      # Print first few kill IDs as examples
      example_kills = Enum.take(kills, 3)

      if length(example_kills) > 0 do
        kill_ids = Enum.map(example_kills, fn {id, _} -> id end)
        Mix.shell().info("  Example Kill IDs: #{Enum.join(kill_ids, ", ")}")
      end
    end)
  end

  defp format_reason(:character_not_found), do: "Character not found in kill"
  defp format_reason(:npc_kill), do: "NPC Kill"
  defp format_reason(:fetch_failed), do: "Failed to fetch kill details"
  defp format_reason(:kill_too_old), do: "Kill is older than 30 days"
  defp format_reason(:not_tracked_at_time), do: "Character wasn't tracked at kill time"
  defp format_reason(:structure_kill), do: "Structure kill"
  defp format_reason(:untracked_system), do: "Kill in untracked system"
  defp format_reason(:potential_duplicate), do: "Potential duplicate kill"
  defp format_reason(:pod_kill), do: "Pod kill"
  defp format_reason(:unknown_reason), do: "Unknown reason"
  defp format_reason(other), do: to_string(other)
end
