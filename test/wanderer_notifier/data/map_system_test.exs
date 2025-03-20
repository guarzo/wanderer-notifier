defmodule WandererNotifier.Data.MapSystemTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Data.MapSystem

  describe "new/1" do
    test "creates a MapSystem from map API response" do
      # Sample API response
      api_response = %{
        "id" => "d5fd1445-e521-4471-b630-d2e97a27b184",
        "name" => "Lor",
        "solar_system_id" => 30005193,
        "temporary_name" => "7-A",
        "original_name" => "Lor",
        "locked" => false
      }
      
      system = MapSystem.new(api_response)
      
      assert system.id == "d5fd1445-e521-4471-b630-d2e97a27b184"
      assert system.solar_system_id == 30005193
      assert system.name == "7-A (Lor)"
      assert system.system_type == :kspace
    end
    
    test "handles missing fields gracefully" do
      # Minimal API response
      api_response = %{
        "id" => "abc123",
        "solar_system_id" => 31001044
      }
      
      system = MapSystem.new(api_response)
      
      assert system.id == "abc123"
      assert system.solar_system_id == 31001044
      assert system.name == "Unknown System"
      assert system.system_type == :wormhole
    end
  end
  
  describe "update_with_static_info/2" do
    test "enriches a MapSystem with static information" do
      # Create a basic system
      system = %MapSystem{
        id: "test-id",
        solar_system_id: 31001044,
        name: "Test System",
        system_type: :wormhole
      }
      
      # Sample static info response
      static_info = %{
        "class_title" => "C3",
        "effect_name" => "Red Giant",
        "static_details" => [
          %{
            "name" => "U210",
            "destination" => %{
              "id" => "ls",
              "name" => "Low-sec",
              "short_name" => "L"
            }
          }
        ]
      }
      
      # Update the system
      updated = MapSystem.update_with_static_info(system, static_info)
      
      assert updated.class_title == "C3"
      assert updated.effect_name == "Red Giant"
      assert length(updated.statics) == 1
      assert hd(updated.statics)["name"] == "U210"
    end
  end
  
  describe "format_display_name/1" do
    test "uses temporary_name with original_name in parentheses when both exist" do
      system = %MapSystem{
        temporary_name: "7-A",
        original_name: "Lor"
      }
      
      display_name = MapSystem.format_display_name(system)
      assert display_name == "7-A (Lor)"
    end
    
    test "uses original_name when temporary_name is nil" do
      system = %MapSystem{
        temporary_name: nil,
        original_name: "Lor"
      }
      
      display_name = MapSystem.format_display_name(system)
      assert display_name == "Lor"
    end
    
    test "falls back to name field if needed" do
      system = %MapSystem{
        temporary_name: nil,
        original_name: nil,
        name: "Fallback Name"
      }
      
      display_name = MapSystem.format_display_name(system)
      assert display_name == "Fallback Name"
    end
    
    test "returns 'Unknown System' when no names are available" do
      system = %MapSystem{
        temporary_name: nil,
        original_name: nil,
        name: nil
      }
      
      display_name = MapSystem.format_display_name(system)
      assert display_name == "Unknown System"
    end
  end
end
