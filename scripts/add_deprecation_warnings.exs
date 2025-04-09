#!/usr/bin/env elixir

# Script to add deprecation warnings to functions in the Killmail module
#
# Usage:
#   mix run scripts/add_deprecation_warnings.exs
#
# This script will:
# 1. Parse the Killmail module file
# 2. Add deprecation warnings to all public functions
# 3. Write the updated file back

defmodule DeprecationWarningAdder do
  @killmail_file "lib/wanderer_notifier/killmail.ex"
  @deprecation_map %{
    # Map function names to their replacements
    "get_system_id" => "WandererNotifier.KillmailProcessing.Extractor.get_system_id/1",
    "get_system_name" => "WandererNotifier.KillmailProcessing.Extractor.get_system_name/1",
    "get_victim" => "WandererNotifier.KillmailProcessing.Extractor.get_victim/1",
    "get_attacker" => "WandererNotifier.KillmailProcessing.Extractor.get_attackers/1",
    "debug_data" => "WandererNotifier.KillmailProcessing.Extractor.debug_data/1",
    "exists?" => "WandererNotifier.KillmailProcessing.KillmailQueries.exists?/1",
    "get" => "WandererNotifier.KillmailProcessing.KillmailQueries.get/1",
    "get_involvements" => "WandererNotifier.KillmailProcessing.KillmailQueries.get_involvements/1",
    "find_by_character" => "WandererNotifier.KillmailProcessing.KillmailQueries.find_by_character/3",
    "validate_complete_data" => "WandererNotifier.KillmailProcessing.Validator.validate_complete_data/1",
    # Add more mappings as needed
  }

  def run do
    IO.puts("Adding deprecation warnings to functions in the Killmail module...")

    # Read the file
    content = File.read!(@killmail_file)

    # Add deprecation warnings
    updated_content = add_deprecation_warnings(content)

    # Write the file back
    File.write!(@killmail_file, updated_content)

    IO.puts("Done! Deprecation warnings added.")
  end

  defp add_deprecation_warnings(content) do
    # For each function in the deprecation map
    Enum.reduce(@deprecation_map, content, fn {function_name, replacement}, acc ->
      # Find the function definition and add deprecation warning
      add_deprecation_to_function(acc, function_name, replacement)
    end)
  end

  defp add_deprecation_to_function(content, function_name, replacement) do
    # Match the function definition
    function_regex = ~r/(\s+@doc\s+"""[^"]*"""\n\s+def #{function_name}[\(\w\s,\:\|\@\{\}\[\]]*do)/

    # Check if the function already has a deprecation warning
    has_deprecation = Regex.match?(~r/@deprecated/, content)

    if Regex.match?(function_regex, content) && !has_deprecation do
      # Add deprecation warning to the function docstring
      Regex.replace(function_regex, content, fn _, match ->
        # Extract the existing docstring
        doc_regex = ~r/(\s+@doc\s+""")(.*?)(\s*""")/s
        {doc_prefix, doc_content, doc_suffix} = case Regex.run(doc_regex, match, capture: :all_but_first) do
          [prefix, content, suffix] -> {prefix, content, suffix}
          _ -> {"\n  @doc \"\"\"", "", "\n  \"\"\""}
        end

        # Add deprecation warning to docstring
        deprecation_msg = "\n  @deprecated Use #{replacement} instead."
        updated_docstring = doc_prefix <> doc_content <> doc_suffix

        # Inject deprecation attribute after the docstring
        [head, tail] = String.split(match, "\n  @doc", parts: 2)
        head <> "\n  @doc" <> tail <> deprecation_msg
      end)
    else
      # No match or already has deprecation warning
      content
    end
  end
end

DeprecationWarningAdder.run()
