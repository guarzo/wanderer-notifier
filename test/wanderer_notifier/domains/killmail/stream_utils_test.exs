defmodule WandererNotifier.Domains.Killmail.StreamUtilsTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Domains.Killmail.StreamUtils

  describe "aggregate_stream_results/1" do
    test "aggregates successful results correctly" do
      stream = [
        {:ok, {:ok, %{"system1" => [1, 2, 3], "system2" => [4, 5]}}},
        {:ok, {:ok, %{"system3" => [6]}}}
      ]

      result = StreamUtils.aggregate_stream_results(stream)

      assert result.loaded == 6
      assert result.errors == []
    end

    test "collects API errors" do
      stream = [
        {:ok, {:ok, %{"system1" => [1, 2]}}},
        {:ok, {:error, "API timeout"}},
        {:ok, {:error, "Rate limited"}}
      ]

      result = StreamUtils.aggregate_stream_results(stream)

      assert result.loaded == 2
      assert result.errors == ["Rate limited", "API timeout"]
    end

    test "handles task errors" do
      stream = [
        {:ok, {:ok, %{"system1" => [1]}}},
        {:error, :timeout},
        {:error, {:exit, :killed}}
      ]

      result = StreamUtils.aggregate_stream_results(stream)

      assert result.loaded == 1
      assert result.errors == [{:task_error, {:exit, :killed}}, {:task_error, :timeout}]
    end

    test "handles empty stream" do
      result = StreamUtils.aggregate_stream_results([])

      assert result.loaded == 0
      assert result.errors == []
    end

    test "handles mixed results" do
      stream = [
        {:ok, {:ok, %{"system1" => [1, 2, 3]}}},
        {:ok, {:error, "API error"}},
        {:error, :task_timeout},
        {:ok, {:ok, %{"system2" => [4, 5]}}}
      ]

      result = StreamUtils.aggregate_stream_results(stream)

      assert result.loaded == 5
      assert result.errors == [{:task_error, :task_timeout}, "API error"]
    end
  end

  describe "count_killmails/1" do
    test "counts killmails from system data map" do
      system_data = %{
        "30000142" => [1, 2, 3],
        "30000143" => [4, 5],
        "30000144" => []
      }

      assert StreamUtils.count_killmails(system_data) == 5
    end

    test "handles empty system data" do
      assert StreamUtils.count_killmails(%{}) == 0
    end

    test "handles non-map input" do
      assert StreamUtils.count_killmails(nil) == 0
      assert StreamUtils.count_killmails("invalid") == 0
      assert StreamUtils.count_killmails([]) == 0
    end
  end
end
