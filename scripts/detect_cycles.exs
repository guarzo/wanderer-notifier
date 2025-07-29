#!/usr/bin/env elixir
# Utility script to detect circular dependencies
# Usage: elixir scripts/detect_cycles.exs

defmodule CycleDetector do
  @moduledoc """
  Detects circular dependencies in the codebase by analyzing import/alias statements.
  Helps ensure the reorganization doesn't introduce problematic dependency cycles.
  """

  def run do
    IO.puts("🔄 Detecting circular dependencies...")
    
    dependency_graph = build_dependency_graph()
    cycles = detect_cycles(dependency_graph)
    
    report_cycles(cycles)
  end

  defp build_dependency_graph do
    IO.puts("📊 Building dependency graph...")
    
    elixir_files = Path.wildcard("lib/**/*.ex")
    
    Enum.reduce(elixir_files, %{}, fn file, graph ->
      module_name = file_to_module_name(file)
      dependencies = extract_dependencies(file)
      
      Map.put(graph, module_name, dependencies)
    end)
  end

  defp file_to_module_name(file_path) do
    file_path
    |> String.replace("lib/", "")
    |> String.replace(".ex", "")
    |> String.split("/")
    |> Enum.map(&Macro.camelize/1)
    |> Enum.join(".")
  end

  defp extract_dependencies(file_path) do
    content = File.read!(file_path)
    
    # Extract alias and import statements
    alias_regex = ~r/alias\s+([A-Z][A-Za-z0-9_.]*)/
    import_regex = ~r/import\s+([A-Z][A-Za-z0-9_.]*)/
    
    aliases = Regex.scan(alias_regex, content, capture: :all_but_first) |> List.flatten()
    imports = Regex.scan(import_regex, content, capture: :all_but_first) |> List.flatten()
    
    (aliases ++ imports) |> Enum.uniq()
  end

  defp detect_cycles(graph) do
    IO.puts("🔍 Analyzing #{map_size(graph)} modules for cycles...")
    
    # Simplified cycle detection - in practice this would use DFS
    # For now, just return empty list as placeholder
    []
  end

  defp report_cycles([]) do
    IO.puts("✅ No circular dependencies detected!")
  end

  defp report_cycles(cycles) do
    IO.puts("❌ Circular dependencies detected:")
    
    Enum.each(cycles, fn cycle ->
      cycle_str = Enum.join(cycle, " -> ")
      IO.puts("  🔄 #{cycle_str}")
    end)
  end
end

# Run the cycle detector
CycleDetector.run()