defmodule WandererNotifier.FeaturesTest do
  use ExUnit.Case
  import Mox
  alias WandererNotifier.Features
  alias WandererNotifier.License

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Start a mock License GenServer
    mock_license = start_supervised!({MockGenServer, name: License, state: %{valid: false}})

    # Return the mock server PID for use in tests
    {:ok, %{mock_license: mock_license}}
  end

  describe "enabled?/1" do
    test "delegates to License.feature_enabled?/1", %{mock_license: mock} do
      feature = "test_feature"
      MockGenServer.expect(mock, :call, fn _, {:feature_enabled, ^feature} -> true end)

      assert Features.enabled?(feature) == true
    end
  end

  describe "premium?/0" do
    test "delegates to License.premium?/0", %{mock_license: mock} do
      MockGenServer.expect(mock, :call, fn _, :premium -> true end)

      assert Features.premium?() == true
    end
  end

  describe "when_enabled/3" do
    test "executes the function when the feature is enabled", %{mock_license: mock} do
      feature = "test_feature"
      MockGenServer.expect(mock, :call, fn _, {:feature_enabled, ^feature} -> true end)

      result =
        Features.when_enabled(feature, fn -> :feature_enabled end, fn -> :feature_disabled end)

      assert result == :feature_enabled
    end

    test "executes the else function when the feature is disabled", %{mock_license: mock} do
      feature = "test_feature"
      MockGenServer.expect(mock, :call, fn _, {:feature_enabled, ^feature} -> false end)

      result =
        Features.when_enabled(feature, fn -> :feature_enabled end, fn -> :feature_disabled end)

      assert result == :feature_disabled
    end

    test "returns nil when the feature is disabled and no else function is provided", %{
      mock_license: mock
    } do
      feature = "test_feature"
      MockGenServer.expect(mock, :call, fn _, {:feature_enabled, ^feature} -> false end)

      result = Features.when_enabled(feature, fn -> :feature_enabled end)
      assert result == nil
    end
  end

  describe "when_premium/2" do
    test "executes the function when premium is enabled", %{mock_license: mock} do
      MockGenServer.expect(mock, :call, fn _, :premium -> true end)

      result = Features.when_premium(fn -> :premium_enabled end, fn -> :premium_disabled end)
      assert result == :premium_enabled
    end

    test "executes the else function when premium is disabled", %{mock_license: mock} do
      MockGenServer.expect(mock, :call, fn _, :premium -> false end)

      result = Features.when_premium(fn -> :premium_enabled end, fn -> :premium_disabled end)
      assert result == :premium_disabled
    end

    test "returns nil when premium is disabled and no else function is provided", %{
      mock_license: mock
    } do
      MockGenServer.expect(mock, :call, fn _, :premium -> false end)

      result = Features.when_premium(fn -> :premium_enabled end)
      assert result == nil
    end
  end
end

# Mock GenServer for testing
defmodule MockGenServer do
  use GenServer

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    state = Keyword.get(opts, :state, %{})
    GenServer.start_link(__MODULE__, state, name: name)
  end

  def init(state) do
    {:ok, {state, %{expectations: []}}}
  end

  def expect(server, type, expectation) do
    GenServer.call(server, {:expect, type, expectation})
  end

  def handle_call({:expect, type, expectation}, _from, {state, %{expectations: expectations}}) do
    {:reply, :ok, {state, %{expectations: [{type, expectation} | expectations]}}}
  end

  def handle_call(message, from, {state, %{expectations: expectations} = meta}) do
    case find_expectation(:call, expectations) do
      nil ->
        raise "No expectation found for call: #{inspect(message)}"

      expectation ->
        result = expectation.(from, message)
        new_expectations = List.delete(expectations, {:call, expectation})
        {:reply, result, {state, %{meta | expectations: new_expectations}}}
    end
  end

  defp find_expectation(type, expectations) do
    case Enum.find(expectations, fn {t, _} -> t == type end) do
      {^type, expectation} -> expectation
      _ -> nil
    end
  end
end
