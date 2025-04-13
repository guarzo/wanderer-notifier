defmodule WandererNotifier.Killmail.Processing.ApiProcessorTest do
  use ExUnit.Case, async: false
  import Mox

  alias WandererNotifier.Killmail.Core.{
    Context,
    Data,
    Mode
  }
  alias WandererNotifier.Killmail.Processing.{
    ApiProcessor
  }
  alias WandererNotifier.Killmail.Processing.MockPersistence
  alias WandererNotifier.Killmail.Processing.MockProcessor

  # Test data
  @killmail_id 12345
  @character_id 98765
  @character_name "Test Character"
  @test_killmail %{
    "killmail_id" => @killmail_id,
    "solar_system_id" => 30000142,
    "victim" => %{
      "character_id" => 87654,
      "ship_type_id" => 587
    },
    "attackers" => [
      %{"character_id" => 12345, "ship_type_id" => 34562}
    ]
  }
  @test_zkb_data %{
    "killmail_id" => @killmail_id,
    "zkb" => %{
      "totalValue" => 1000000.0,
      "points" => 10
    }
  }

  setup :verify_on_exit!

  setup do
    # Set up mock modules
    Application.put_env(:wanderer_notifier, :persistence, MockPersistence)
    Application.put_env(:wanderer_notifier, :processor, MockProcessor)

    # Default Persistence mock behavior
    stub(MockPersistence, :exists?, fn _ -> false end)

    # Default Processor mock behavior
    stub(MockProcessor, :process_killmail, fn _, _ ->
      {:ok, %Data{killmail_id: @killmail_id}}
    end)

    :ok
  end

  describe "process_api_killmail/2" do
    test "successfully processes new killmail" do
      # Set up the expectation for the processor call
      expect(MockProcessor, :process_killmail, fn killmail, context ->
        # Verify killmail data is created correctly
        assert killmail.killmail_id == @killmail_id
        assert context.character_id == @character_id
        assert context.character_name == @character_name
        assert context.mode == :api

        {:ok, killmail}
      end)

      # Create API processing context
      context = Context.new_api(@character_id, @character_name)

      # Call the API processor
      result = ApiProcessor.process_api_killmail(@test_killmail, @test_zkb_data, context)

      # Verify successful processing
      assert {:ok, killmail} = result
      assert killmail.killmail_id == @killmail_id
    end

    test "skips processing for existing killmail" do
      # Mock that killmail exists in database
      stub(MockPersistence, :exists?, fn id ->
        assert id == @killmail_id
        true
      end)

      # No processing should happen - processor shouldn't be called

      # Create API processing context
      context = Context.new_api(@character_id, @character_name)

      # Call the API processor
      result = ApiProcessor.process_api_killmail(@test_killmail, @test_zkb_data, context)

      # Verify skipped due to existence
      assert {:ok, :already_processed} = result
    end

    test "can force processing of existing killmail" do
      # Mock that killmail exists in database
      stub(MockPersistence, :exists?, fn id ->
        assert id == @killmail_id
        true
      end)

      # But force processing should still call the processor
      expect(MockProcessor, :process_killmail, fn killmail, context ->
        # Verify killmail data is created correctly
        assert killmail.killmail_id == @killmail_id
        assert context.force_processing == true

        {:ok, killmail}
      end)

      # Create API processing context with force flag
      context = Context.new_api(@character_id, @character_name)
      context = %{context | force_processing: true}

      # Call the API processor
      result = ApiProcessor.process_api_killmail(@test_killmail, @test_zkb_data, context)

      # Verify successful forced processing
      assert {:ok, killmail} = result
      assert killmail.killmail_id == @killmail_id
    end

    test "handles invalid ESI data" do
      # Call with invalid ESI data
      invalid_esi = %{"not_a_killmail" => true}
      context = Context.new_api(@character_id, @character_name)

      result = ApiProcessor.process_api_killmail(invalid_esi, @test_zkb_data, context)

      # Should return error
      assert {:error, :invalid_killmail_data} = result
    end

    test "handles invalid zKillboard data" do
      # Call with invalid zkb data
      invalid_zkb = %{"not_zkb_data" => true}
      context = Context.new_api(@character_id, @character_name)

      result = ApiProcessor.process_api_killmail(@test_killmail, invalid_zkb, context)

      # Should return error
      assert {:error, :invalid_zkb_data} = result
    end

    test "handles processor errors" do
      # Mock processor to return error
      stub(MockProcessor, :process_killmail, fn _, _ ->
        {:error, :processing_failed}
      end)

      context = Context.new_api(@character_id, @character_name)

      result = ApiProcessor.process_api_killmail(@test_killmail, @test_zkb_data, context)

      # Should propagate error from processor
      assert {:error, :processing_failed} = result
    end
  end

  describe "process_killmail_id/2" do
    test "fetches and processes killmail by ID" do
      killmail_id = @killmail_id
      context = Context.new_api(@character_id, @character_name)

      # TODO: This should mock EVE ESI client and test the full flow
      # This is a placeholder that would need real API mocks to be properly tested

      # For now, we can't fully test this without mocking the external ESI client
      # This would be covered in a more comprehensive integration test
    end
  end
end
