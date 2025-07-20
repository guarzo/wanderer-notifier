defmodule NotificationBench do
  use Benchfella
  alias WandererNotifier.Domains.Notifications.NotificationService

  @test_killmail %{
    "killmail_id" => 123456,
    "killmail_time" => "2024-01-01T12:00:00Z",
    "solar_system_id" => 30000142,
    "victim" => %{
      "character_id" => 93345033,
      "corporation_id" => 98553333,
      "ship_type_id" => 602,
      "damage_taken" => 1000
    },
    "attackers" => [
      %{
        "character_id" => 12345678,
        "corporation_id" => 87654321,
        "ship_type_id" => 670,
        "damage_done" => 1000,
        "final_blow" => true
      }
    ],
    "zkb" => %{
      "locationID" => 40009056,
      "hash" => "abc123",
      "fittedValue" => 150000000,
      "totalValue" => 150000000,
      "points" => 10,
      "npc" => false,
      "solo" => false,
      "awox" => false
    }
  }

  @test_notification %{
    type: :kill_notification,
    data: %{killmail: @test_killmail},
    source: :benchmark
  }

  setup_all do
    # Set up mock services to avoid real Discord/network calls
    Application.put_env(:wanderer_notifier, :discord_notifier, NotificationBenchMock)
    
    # Create a simple mock for notifications
    defmodule NotificationBenchMock do
      def send_notification(_notification, _options \\ []) do
        {:ok, %{id: "benchmark_notification_#{:rand.uniform(1000)}"}}
      end
      
      def format_killmail(_killmail) do
        "Mock killmail notification for benchmarking"
      end
    end

    {:ok, []}
  end

  bench "notification processing basic" do
    # Mock the notification service call
    %{
      type: @test_notification.type,
      processed_at: ~U[2024-01-01 12:00:00Z],
      result: :success
    }
  end

  bench "killmail data transformation" do
    # Simulate the data transformation process
    %{
      killmail_id: @test_killmail["killmail_id"],
      value: @test_killmail["zkb"]["totalValue"],
      system_id: @test_killmail["solar_system_id"],
      victim_character: @test_killmail["victim"]["character_id"],
      formatted_at: ~U[2024-01-01 12:00:00Z]
    }
  end

  bench "notification eligibility check" do
    # Simulate checking if notification should be sent
    killmail = @test_killmail
    value = killmail["zkb"]["totalValue"]
    
    # Mock eligibility logic
    cond do
      value > 100_000_000 -> :eligible
      value > 50_000_000 -> :maybe_eligible  
      true -> :not_eligible
    end
  end

  bench "notification formatting" do
    # Simulate Discord message formatting
    killmail = @test_killmail
    victim_name = "Test Victim"
    attacker_name = "Test Attacker"
    ship_name = "Retriever"
    system_name = "Jita"
    
    """
    💀 **#{victim_name}** lost a **#{ship_name}** in **#{system_name}**
    🔸 **Value:** #{killmail["zkb"]["totalValue"]} ISK
    🔸 **Attacker:** #{attacker_name}
    🔸 **Time:** #{killmail["killmail_time"]}
    """
  end

  bench "deduplication check" do
    # Simulate checking if killmail was already processed
    killmail_id = @test_killmail["killmail_id"]
    _cache_key = "dedup:killmail:#{killmail_id}"
    
    # Mock cache check (always return :new for consistent benchmarks)
    :new
  end
end