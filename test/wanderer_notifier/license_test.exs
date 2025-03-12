defmodule WandererNotifier.LicenseTest do
  use ExUnit.Case
  import Mox
  alias WandererNotifier.License
  alias WandererNotifier.TestHelpers
  
  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!
  
  setup do
    # Set up environment variables for testing
    Application.put_env(:wanderer_notifier, :license_key, "test-license-key")
    
    # Start the License GenServer for each test
    start_supervised!(License)
    
    :ok
  end
  
  describe "validate/0" do
    test "returns true when the license is valid" do
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response())
      
      assert License.validate() == true
    end
    
    test "returns false when the license is invalid" do
      TestHelpers.setup_license_mock(TestHelpers.invalid_license_response())
      
      assert License.validate() == false
    end
    
    test "returns false when the license key is not configured" do
      Application.delete_env(:wanderer_notifier, :license_key)
      
      assert License.validate() == false
    end
  end
  
  describe "status/0" do
    test "returns valid status when the license is valid" do
      response = TestHelpers.valid_license_response()
      TestHelpers.setup_license_mock(response)
      
      # Trigger validation
      License.validate()
      
      status = License.status()
      assert status.valid == true
      assert status.details == elem(response, 1)
    end
    
    test "returns invalid status with error when the license is invalid" do
      error = :license_not_found
      TestHelpers.setup_license_mock(TestHelpers.invalid_license_response(error))
      
      # Trigger validation
      License.validate()
      
      status = License.status()
      assert status.valid == false
      assert status.error == error
    end
  end
  
  describe "feature_enabled?/1" do
    test "returns true when the feature is enabled" do
      features = ["feature1", "feature2"]
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response(features))
      
      # Trigger validation
      License.validate()
      
      assert License.feature_enabled?("feature1") == true
      assert License.feature_enabled?("feature2") == true
    end
    
    test "returns false when the feature is not enabled" do
      features = ["feature1"]
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response(features))
      
      # Trigger validation
      License.validate()
      
      assert License.feature_enabled?("feature2") == false
    end
    
    test "returns false when the license is invalid" do
      TestHelpers.setup_license_mock(TestHelpers.invalid_license_response())
      
      # Trigger validation
      License.validate()
      
      assert License.feature_enabled?("feature1") == false
    end
  end
  
  describe "premium?/0" do
    test "returns true when the license tier is premium" do
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response(["feature1"], "premium"))
      
      # Trigger validation
      License.validate()
      
      assert License.premium?() == true
    end
    
    test "returns true when the license tier is enterprise" do
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response(["feature1"], "enterprise"))
      
      # Trigger validation
      License.validate()
      
      assert License.premium?() == true
    end
    
    test "returns false when the license tier is not premium or enterprise" do
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response(["feature1"], "basic"))
      
      # Trigger validation
      License.validate()
      
      assert License.premium?() == false
    end
    
    test "returns false when the license is invalid" do
      TestHelpers.setup_license_mock(TestHelpers.invalid_license_response())
      
      # Trigger validation
      License.validate()
      
      assert License.premium?() == false
    end
  end
  
  describe "periodic refresh" do
    test "refreshes the license after the refresh interval" do
      TestHelpers.setup_license_mock(TestHelpers.valid_license_response())
      
      # Trigger initial validation
      assert License.validate() == true
      
      # Change the mock to return invalid license
      TestHelpers.setup_license_mock(TestHelpers.invalid_license_response())
      
      # Manually trigger refresh
      send(License, :refresh)
      
      # Wait for the GenServer to process the message
      :timer.sleep(100)
      
      # Check that the license status has been updated
      assert License.validate() == false
    end
  end
end 