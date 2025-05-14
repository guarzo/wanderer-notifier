defmodule WandererNotifier.Debug.ChartService do
  @moduledoc """
  A debugging script to identify references to chart_service_dir in compiled code.

  Run with: mix run scripts/debug_chart_service.ex
  """

  def find_references do
    IO.puts("Checking for chart_service_dir references in the application...")

    # Check current application environment
    IO.puts("\nApplication environment:")
    :wanderer_notifier
    |> Application.get_all_env()
    |> Enum.each(fn {key, value} ->
      IO.puts("  #{inspect(key)}: #{inspect(value)}")
    end)

    # List any modules that might use Application.compile_env
    IO.puts("\nModules with potential compile_env usage:")
    for module <- :code.all_loaded() do
      {mod, _} = module
      if is_atom(mod) && to_string(mod) =~ "WandererNotifier" do
        try do
          module_info = mod.module_info()
          attributes = Keyword.get(module_info, :attributes, [])

          if attributes != [] do
            chart_related =
              attributes
              |> Enum.filter(fn {_, values} ->
                values
                |> inspect
                |> String.downcase
                |> String.contains?("chart")
              end)

            if chart_related != [] do
              IO.puts("  #{inspect(mod)}: #{inspect(chart_related)}")
            end
          end
        rescue
          _ -> :ok
        end
      end
    end

    IO.puts("\nDebug complete!")
  end
end

WandererNotifier.Debug.ChartService.find_references()
