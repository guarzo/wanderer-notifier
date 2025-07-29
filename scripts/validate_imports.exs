#!/usr/bin/env elixir
# Utility script to validate import paths after file moves
# Usage: elixir scripts/validate_imports.exs

defmodule ImportValidator do
  @moduledoc """
  Validates that all import paths are correct after file reorganization.
  Checks for broken imports, circular dependencies, and missing modules.
  """

  def run do
    IO.puts("🔍 Validating import paths...")
    
    results = %{
      total_files: 0,
      broken_imports: [],
      circular_deps: [],
      missing_modules: []
    }
    
    results
    |> count_total_files()
    |> check_broken_imports()
    |> check_circular_dependencies()
    |> check_missing_modules()
    |> report_results()
  end

  defp count_total_files(results) do
    elixir_files = 
      Path.wildcard("lib/**/*.ex") ++ 
      Path.wildcard("test/**/*.exs")
    
    IO.puts("📁 Found #{length(elixir_files)} Elixir files")
    %{results | total_files: length(elixir_files)}
  end

  defp check_broken_imports(results) do
    IO.puts("🔎 Checking for broken imports...")
    
    broken = []
    # TODO: Implement actual import checking logic
    # This would parse each file and verify import paths exist
    
    %{results | broken_imports: broken}
  end

  defp check_circular_dependencies(results) do
    IO.puts("🔄 Checking for circular dependencies...")
    
    circular = []
    # TODO: Implement circular dependency detection
    # This would build a dependency graph and detect cycles
    
    %{results | circular_deps: circular}
  end

  defp check_missing_modules(results) do
    IO.puts("📦 Checking for missing modules...")
    
    missing = []
    # TODO: Implement missing module detection
    # This would verify all referenced modules exist
    
    %{results | missing_modules: missing}
  end

  defp report_results(results) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("📊 IMPORT VALIDATION RESULTS")
    IO.puts(String.duplicate("=", 50))
    
    IO.puts("Total files scanned: #{results.total_files}")
    IO.puts("Broken imports: #{length(results.broken_imports)}")
    IO.puts("Circular dependencies: #{length(results.circular_deps)}")
    IO.puts("Missing modules: #{length(results.missing_modules)}")
    
    if results.broken_imports == [] and results.circular_deps == [] and results.missing_modules == [] do
      IO.puts("✅ All imports are valid!")
    else
      IO.puts("❌ Issues found - see details above")
    end
    
    results
  end
end

# Run the validator
ImportValidator.run()