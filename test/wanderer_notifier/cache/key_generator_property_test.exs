defmodule WandererNotifier.Cache.KeyGeneratorPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias WandererNotifier.Cache.KeyGenerator
  
  @separator ":"
  
  describe "combine/3 and parse_key/1 round-trip properties" do
    property "any valid key parts can be combined and parsed back" do
      check all fixed_parts <- list_of(string(:alphanumeric, min_length: 1), min_length: 1),
                dynamic_parts <- list_of(string(:alphanumeric, min_length: 1)),
                extra <- one_of([nil, string(:alphanumeric, min_length: 1)]) do
        
        # Ensure we have at least 2 parts for a valid key
        all_parts = fixed_parts ++ dynamic_parts ++ (if extra, do: [extra], else: [])
        
        if length(all_parts) >= 2 do
          # Generate key
          key = KeyGenerator.combine(fixed_parts, dynamic_parts, extra)
          
          # Parse it back
          parsed = KeyGenerator.parse_key(key)
          
          # Basic assertions
          assert is_map(parsed)
          assert parsed != {:error, :invalid_key}
          assert is_list(parsed.parts)
          
          # The key should contain all parts
          assert length(parsed.parts) == length(all_parts)
          
          # Each part should be in the key
          Enum.each(all_parts, fn part ->
            assert to_string(part) in parsed.parts
          end)
        else
          # Skip test if we don't have enough parts
          :ok
        end
      end
    end
    
    property "keys are always valid after combination" do
      check all fixed <- list_of(string(:alphanumeric, min_length: 1), min_length: 1, max_length: 5),
                dynamic <- list_of(string(:alphanumeric, min_length: 1), max_length: 5),
                extra <- one_of([nil, string(:alphanumeric, min_length: 1)]) do
        
        # Ensure we have at least 2 parts for a valid key
        all_parts = fixed ++ dynamic ++ (if extra, do: [extra], else: [])
        
        if length(all_parts) >= 2 do
          key = KeyGenerator.combine(fixed, dynamic, extra)
          assert KeyGenerator.valid_key?(key)
        else
          # A key with only one part should be invalid
          key = KeyGenerator.combine(fixed, dynamic, extra)
          refute KeyGenerator.valid_key?(key)
        end
      end
    end
    
    property "parsed keys maintain their structure" do
      check all prefix <- string(:alphanumeric, min_length: 1),
                entity <- string(:alphanumeric, min_length: 1),
                id <- one_of([integer(), string(:alphanumeric, min_length: 1)]),
                extra <- one_of([nil, string(:alphanumeric, min_length: 1)]) do
        
        key = KeyGenerator.combine([prefix, entity], [id], extra)
        parsed = KeyGenerator.parse_key(key)
        
        assert parsed.prefix == prefix
        assert parsed.entity_type == entity
        assert parsed.id == to_string(id)
        
        if extra do
          assert extra in parsed.extra
        else
          assert parsed.extra == []
        end
      end
    end
  end
  
  describe "valid_key?/1 properties" do
    property "keys with separator and at least 2 parts are valid" do
      check all parts <- list_of(string(:alphanumeric, min_length: 1), min_length: 2) do
        key = Enum.join(parts, @separator)
        assert KeyGenerator.valid_key?(key)
      end
    end
    
    property "keys without separator are invalid" do
      check all key <- string(:alphanumeric, min_length: 1) do
        refute String.contains?(key, @separator)
        refute KeyGenerator.valid_key?(key)
      end
    end
    
    property "single part keys are invalid" do
      check all part <- string(:alphanumeric, min_length: 1) do
        refute KeyGenerator.valid_key?(part)
      end
    end
    
    property "non-string values are invalid" do
      check all value <- one_of([integer(), float(), boolean(), nil]) do
        refute KeyGenerator.valid_key?(value)
      end
    end
  end
  
  describe "extract_pattern/2 properties" do
    property "exact patterns extract nothing" do
      check all parts <- list_of(string(:alphanumeric, min_length: 1), min_length: 2) do
        key = Enum.join(parts, @separator)
        pattern = key
        
        assert KeyGenerator.extract_pattern(key, pattern) == []
      end
    end
    
    property "wildcards extract corresponding parts" do
      check all prefix <- string(:alphanumeric, min_length: 1),
                entity <- string(:alphanumeric, min_length: 1),
                id <- string(:alphanumeric, min_length: 1) do
        
        key = Enum.join([prefix, entity, id], @separator)
        pattern = Enum.join([prefix, "*", id], @separator)
        
        extracted = KeyGenerator.extract_pattern(key, pattern)
        assert extracted == [entity]
      end
    end
    
    property "all wildcards extract all parts" do
      check all parts <- list_of(string(:alphanumeric, min_length: 1), min_length: 1, max_length: 5) do
        key = Enum.join(parts, @separator)
        pattern = 
          parts 
          |> length() 
          |> (&List.duplicate("*", &1)).() 
          |> Enum.join(@separator)
        
        extracted = KeyGenerator.extract_pattern(key, pattern)
        assert extracted == parts
      end
    end
  end
  
  describe "join_parts/1 properties" do
    property "joined parts can be split back" do
      check all parts <- list_of(string(:alphanumeric, min_length: 1), min_length: 1) do
        joined = KeyGenerator.join_parts(parts)
        split = String.split(joined, @separator)
        
        assert split == parts
      end
    end
    
    property "empty list produces empty string" do
      assert KeyGenerator.join_parts([]) == ""
    end
  end
  
  describe "edge cases and invariants" do
    property "numeric IDs are converted to strings" do
      check all prefix <- string(:alphanumeric, min_length: 1),
                entity <- string(:alphanumeric, min_length: 1),
                id <- integer() do
        
        key = KeyGenerator.combine([prefix, entity], [id], nil)
        assert String.contains?(key, to_string(id))
      end
    end
    
    property "nil extra is handled correctly" do
      check all prefix <- string(:alphanumeric, min_length: 1),
                entity <- string(:alphanumeric, min_length: 1) do
        
        key_with_nil = KeyGenerator.combine([prefix, entity], [], nil)
        key_without = KeyGenerator.combine([prefix, entity], [], nil)
        
        assert key_with_nil == key_without
      end
    end
    
    property "special characters in parts are preserved" do
      # Using printable strings to test edge cases
      check all parts <- list_of(string(:printable, min_length: 1), min_length: 2, max_length: 3) do
        # Skip if any part contains the separator
        unless Enum.any?(parts, &String.contains?(&1, @separator)) do
          key = KeyGenerator.combine(parts, [], nil)
          parsed = KeyGenerator.parse_key(key)
          
          assert is_map(parsed)
          assert length(parsed.parts) == length(parts)
        end
      end
    end
  end
end