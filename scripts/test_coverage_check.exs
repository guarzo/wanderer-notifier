#!/usr/bin/env elixir
# Utility script to verify test coverage after reorganization
# Usage: elixir scripts/test_coverage_check.exs

defmodule TestCoverageChecker do
  @moduledoc """
  Verifies that test coverage is maintained after file reorganization.
  Ensures we don't lose test coverage during the migration.
  """

  def run do
    IO.puts("🧪 Checking test coverage...")
    
    results = %{
      source_files: [],
      test_files: [],
      coverage_gaps: [],
      total_coverage: 0.0
    }
    
    results
    |> collect_source_files()
    |> collect_test_files()
    |> identify_coverage_gaps()
    |> calculate_coverage()
    |> report_coverage()
  end

  defp collect_source_files(results) do
    source_files = 
      Path.wildcard("lib/**/*.ex")
      |> Enum.reject(&String.contains?(&1, "/test"))
      |> Enum.sort()
    
    IO.puts("📁 Found #{length(source_files)} source files")
    %{results | source_files: source_files}
  end

  defp collect_test_files(results) do
    test_files = 
      Path.wildcard("test/**/*.exs")
      |> Enum.sort()
    
    IO.puts("🧪 Found #{length(test_files)} test files")
    %{results | test_files: test_files}
  end

  defp identify_coverage_gaps(results) do
    IO.puts("🔍 Identifying coverage gaps...")
    
    # Simple heuristic: check if source file has corresponding test
    gaps = 
      Enum.filter(results.source_files, fn source_file ->
        module_name = extract_module_name(source_file)
        test_pattern = "test/**/#{String.downcase(module_name)}*test.exs"
        
        Path.wildcard(test_pattern) == []
      end)
    
    IO.puts("⚠️  Found #{length(gaps)} files without direct test coverage")
    %{results | coverage_gaps: gaps}
  end

  defp extract_module_name(file_path) do
    file_path
    |> Path.basename(".ex")
    |> String.split("_")
    |> List.last()
  end

  defp calculate_coverage(results) do
    total_files = length(results.source_files)
    covered_files = total_files - length(results.coverage_gaps)
    coverage = if total_files > 0, do: (covered_files / total_files) * 100, else: 0.0
    
    %{results | total_coverage: coverage}
  end

  defp report_coverage(results) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("📊 TEST COVERAGE REPORT")
    IO.puts(String.duplicate("=", 50))
    
    IO.puts("Total source files: #{length(results.source_files)}")
    IO.puts("Total test files: #{length(results.test_files)}")
    IO.puts("Files without tests: #{length(results.coverage_gaps)}")
    IO.puts("Approximate coverage: #{Float.round(results.total_coverage, 1)}%")
    
    if results.coverage_gaps != [] do
      IO.puts("\n📋 Files missing test coverage:")
      Enum.each(results.coverage_gaps, fn file ->
        IO.puts("  - #{file}")
      end)
    end
    
    cond do
      results.total_coverage >= 80.0 ->
        IO.puts("✅ Good test coverage!")
      results.total_coverage >= 60.0 ->
        IO.puts("⚠️  Moderate test coverage - consider adding more tests")
      true ->
        IO.puts("❌ Low test coverage - significant gaps detected")
    end
    
    results
  end
end

# Run the coverage checker
TestCoverageChecker.run()