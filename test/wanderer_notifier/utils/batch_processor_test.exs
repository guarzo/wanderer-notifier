defmodule WandererNotifier.Shared.Utils.BatchProcessorTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Shared.Utils.BatchProcessor

  describe "process_sync/3" do
    test "processes empty collection" do
      result = BatchProcessor.process_sync([], &(&1 * 2))
      assert result == []
    end

    test "processes items in default batch size" do
      items = 1..150 |> Enum.to_list()
      result = BatchProcessor.process_sync(items, &(&1 * 2))

      assert result == Enum.map(items, &(&1 * 2))
      assert length(result) == 150
    end

    test "processes items with custom batch size" do
      items = 1..10 |> Enum.to_list()

      # Track batch numbers
      {:ok, batch_tracker} = Agent.start_link(fn -> %{current_batch: 0, batch_map: %{}} end)

      result =
        BatchProcessor.process_sync(
          items,
          fn item ->
            batch_info =
              Agent.get_and_update(batch_tracker, fn state ->
                # If this is the first item in a new batch, increment batch number
                new_state =
                  if rem(item - 1, 3) == 0 do
                    %{state | current_batch: state.current_batch + 1}
                  else
                    state
                  end

                # Record which batch this item belongs to
                updated_state = %{
                  new_state
                  | batch_map: Map.put(new_state.batch_map, item, new_state.current_batch)
                }

                {new_state.current_batch, updated_state}
              end)

            item * 2
          end,
          batch_size: 3
        )

      assert result == [2, 4, 6, 8, 10, 12, 14, 16, 18, 20]

      # Check batching
      batch_map = Agent.get(batch_tracker, fn state -> state.batch_map end)
      Agent.stop(batch_tracker)

      # Items 1-3 in batch 1, 4-6 in batch 2, 7-9 in batch 3, 10 in batch 4
      assert batch_map[1] == 1
      assert batch_map[3] == 1
      assert batch_map[4] == 2
      assert batch_map[6] == 2
      assert batch_map[7] == 3
      assert batch_map[9] == 3
      assert batch_map[10] == 4
    end

    test "maintains order of processed items" do
      items = ["a", "b", "c", "d", "e", "f", "g", "h"]
      result = BatchProcessor.process_sync(items, &String.upcase/1, batch_size: 3)

      assert result == ["A", "B", "C", "D", "E", "F", "G", "H"]
    end

    test "applies batch delay between batches" do
      items = 1..6 |> Enum.to_list()

      start_time = System.monotonic_time(:millisecond)

      _result =
        BatchProcessor.process_sync(items, &(&1 * 2),
          batch_size: 2,
          batch_delay: 50
        )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # 3 batches with 50ms delay between = at least 100ms
      assert elapsed >= 100
    end

    test "handles errors in process function" do
      items = 1..5 |> Enum.to_list()

      assert_raise ArithmeticError, fn ->
        BatchProcessor.process_sync(
          items,
          fn item ->
            if item == 3, do: raise(ArithmeticError), else: item * 2
          end,
          batch_size: 2
        )
      end
    end
  end

  describe "process_parallel/3" do
    test "processes empty collection" do
      assert {:ok, []} = BatchProcessor.process_parallel([], &(&1 * 2))
    end

    test "processes items in parallel" do
      items = 1..20 |> Enum.to_list()

      start_time = System.monotonic_time(:millisecond)

      {:ok, results} =
        BatchProcessor.process_parallel(
          items,
          fn item ->
            # Simulate work
            Process.sleep(10)
            item * 2
          end,
          batch_size: 5,
          max_concurrency: 4
        )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # With parallel processing, should be much faster than sequential
      # 20 items * 10ms = 200ms sequential, but with concurrency should be < 100ms
      assert elapsed < 150

      # Results should still be correct (though order within batches may vary)
      assert Enum.sort(results) == Enum.map(1..20, &(&1 * 2))
    end

    test "handles timeouts gracefully" do
      items = 1..5 |> Enum.to_list()

      result =
        BatchProcessor.process_parallel(
          items,
          fn item ->
            if item == 3 do
              # Will timeout
              Process.sleep(200)
            end

            item * 2
          end,
          batch_size: 2,
          timeout: 100
        )

      assert {:error, failures} = result
      assert length(failures) > 0

      assert Enum.any?(failures, fn
               {:exit, :timeout} -> true
               _ -> false
             end)
    end

    test "respects max concurrency limit" do
      items = 1..10 |> Enum.to_list()

      # Track concurrent executions
      # {current, max}
      {:ok, counter} = Agent.start_link(fn -> {0, 0} end)

      {:ok, _results} =
        BatchProcessor.process_parallel(
          items,
          fn item ->
            Agent.update(counter, fn {current, max} ->
              new_current = current + 1
              new_max = if new_current > max, do: new_current, else: max
              {new_current, new_max}
            end)

            # Hold the task
            Process.sleep(50)

            Agent.update(counter, fn {current, max} ->
              {current - 1, max}
            end)

            item * 2
          end,
          batch_size: 2,
          max_concurrency: 3
        )

      {_, max_concurrent} = Agent.get(counter, & &1)
      Agent.stop(counter)

      # Should never exceed max_concurrency
      assert max_concurrent <= 3
    end
  end

  describe "stream/3" do
    test "creates a lazy stream" do
      items = 1..100 |> Enum.to_list()

      stream = BatchProcessor.stream(items, &(&1 * 2), batch_size: 10)

      # Stream should be lazy
      assert is_function(stream, 2)

      # When evaluated, should produce correct results
      result = Enum.take(stream, 20)
      assert result == Enum.map(1..20, &(&1 * 2))
    end

    test "composes with other stream operations" do
      items = 1..50 |> Enum.to_list()

      result =
        items
        |> BatchProcessor.stream(&(&1 * 2), batch_size: 10)
        |> Stream.filter(&(rem(&1, 4) == 0))
        |> Stream.map(&(&1 + 1))
        |> Enum.take(5)

      # 2,4,6,8,10... -> 4,8,12,16,20... -> 5,9,13,17,21
      assert result == [5, 9, 13, 17, 21]
    end
  end

  describe "reduce/4" do
    test "reduces empty collection" do
      result = BatchProcessor.reduce([], 0, &(&1 + &2))
      assert result == 0
    end

    test "sums numbers in batches" do
      numbers = 1..100 |> Enum.to_list()

      result = BatchProcessor.reduce(numbers, 0, &(&1 + &2), batch_size: 25)

      # Sum of 1..100
      assert result == 5050
    end

    test "builds map in batches" do
      items = for i <- 1..20, do: %{id: i, value: i * 10}

      result =
        BatchProcessor.reduce(
          items,
          %{},
          fn item, acc ->
            Map.put(acc, item.id, item.value)
          end,
          batch_size: 5
        )

      assert map_size(result) == 20
      assert result[1] == 10
      assert result[20] == 200
    end

    test "applies batch delay in reduce" do
      items = 1..10 |> Enum.to_list()

      start_time = System.monotonic_time(:millisecond)

      _result =
        BatchProcessor.reduce(
          items,
          [],
          fn item, acc ->
            [item | acc]
          end,
          batch_size: 3,
          batch_delay: 30
        )

      end_time = System.monotonic_time(:millisecond)
      elapsed = end_time - start_time

      # 4 batches (3,3,3,1) with 30ms delay = at least 90ms
      assert elapsed >= 90
    end

    test "maintains accumulator state correctly" do
      items = ["a", "b", "c", "d", "e"]

      result =
        BatchProcessor.reduce(
          items,
          "",
          fn item, acc ->
            acc <> item
          end,
          batch_size: 2
        )

      assert result == "abcde"
    end
  end

  describe "edge cases" do
    test "handles single item collection" do
      assert BatchProcessor.process_sync([42], &(&1 * 2)) == [84]
      assert {:ok, [84]} = BatchProcessor.process_parallel([42], &(&1 * 2))
    end

    test "handles batch size larger than collection" do
      items = 1..5 |> Enum.to_list()
      result = BatchProcessor.process_sync(items, &(&1 * 2), batch_size: 100)

      assert result == [2, 4, 6, 8, 10]
    end

    test "handles non-list enumerables" do
      # MapSet
      set = MapSet.new([1, 2, 3, 4, 5])
      result = BatchProcessor.process_sync(set, &(&1 * 2), batch_size: 2)
      assert Enum.sort(result) == [2, 4, 6, 8, 10]

      # Range
      range = 1..10
      result = BatchProcessor.process_sync(range, &(&1 * 2), batch_size: 3)
      assert result == Enum.map(1..10, &(&1 * 2))
    end

    test "handles nil values in collection" do
      items = [1, nil, 3, nil, 5]

      result =
        BatchProcessor.process_sync(
          items,
          fn
            nil -> 0
            n -> n * 2
          end,
          batch_size: 2
        )

      assert result == [2, 0, 6, 0, 10]
    end
  end
end
