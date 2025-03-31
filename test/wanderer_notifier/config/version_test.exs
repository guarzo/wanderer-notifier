defmodule WandererNotifier.Config.VersionTest do
  use ExUnit.Case
  alias WandererNotifier.Config.Version

  describe "version/0" do
    test "returns a valid semantic version string" do
      version = Version.version()
      assert is_binary(version)
      # Validate it matches semantic versioning pattern (x.y.z)
      assert Regex.match?(~r/^\d+\.\d+\.\d+$/, version)
    end
  end

  describe "version_tuple/0" do
    test "returns a tuple of integers" do
      version_tuple = Version.version_tuple()
      assert is_tuple(version_tuple)
      assert tuple_size(version_tuple) == 3
      assert is_integer(elem(version_tuple, 0))
      assert is_integer(elem(version_tuple, 1))
      assert is_integer(elem(version_tuple, 2))
    end
  end

  describe "version_info/0" do
    test "returns a map with version components" do
      info = Version.version_info()
      assert is_map(info)
      assert Map.has_key?(info, :version)
      assert Map.has_key?(info, :major)
      assert Map.has_key?(info, :minor)
      assert Map.has_key?(info, :patch)
      assert is_integer(info.major)
      assert is_integer(info.minor)
      assert is_integer(info.patch)
    end
  end

  describe "at_least?/1" do
    test "correctly compares versions" do
      version = Version.version()
      [major, minor, patch] = String.split(version, ".") |> Enum.map(&String.to_integer/1)

      # Same version returns true
      assert Version.at_least?(version)

      # Lower version returns true
      assert Version.at_least?("#{major - 1}.#{minor}.#{patch}")
      assert Version.at_least?("#{major}.#{minor - 1}.#{patch}")
      assert Version.at_least?("#{major}.#{minor}.#{patch - 1}")

      # Higher version returns false
      refute Version.at_least?("#{major + 1}.#{minor}.#{patch}")
      refute Version.at_least?("#{major}.#{minor + 1}.#{patch}")
      refute Version.at_least?("#{major}.#{minor}.#{patch + 1}")
    end
  end
end
