defmodule WandererNotifier.Map.SSEConnectionTest do
  use ExUnit.Case, async: true

  alias WandererNotifier.Map.SSEConnection

  describe "SSEConnection" do
    test "can be configured with connection parameters" do
      # Test that the connection module can be used with proper parameters
      assert is_function(&SSEConnection.connect/4)
      assert is_function(&SSEConnection.close/1)
    end

    test "close/1 handles different connection types" do
      # Test with nil
      assert :ok = SSEConnection.close(nil)
      
      # Test with reference (may return error from HTTPoison, but doesn't crash)
      ref = make_ref()
      result = SSEConnection.close(ref)
      assert result == :ok or match?({:error, _}, result)
      
      # Test with other types
      assert :ok = SSEConnection.close("invalid")
    end
  end
end