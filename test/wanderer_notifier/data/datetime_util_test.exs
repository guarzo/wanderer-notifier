defmodule WandererNotifier.Data.DateTimeUtilTest do
  use ExUnit.Case

  alias WandererNotifier.Data.DateTimeUtil

  describe "parse_datetime/1" do
    test "handles nil value" do
      assert DateTimeUtil.parse_datetime(nil) == nil
    end

    test "handles DateTime struct" do
      dt = DateTime.from_naive!(~N[2023-01-01 12:00:00], "Etc/UTC")
      assert DateTimeUtil.parse_datetime(dt) == dt
    end

    test "parses valid ISO 8601 string" do
      iso_string = "2023-02-15T08:30:45Z"
      expected = DateTime.from_naive!(~N[2023-02-15 08:30:45], "Etc/UTC")

      result = DateTimeUtil.parse_datetime(iso_string)

      assert result.year == expected.year
      assert result.month == expected.month
      assert result.day == expected.day
      assert result.hour == expected.hour
      assert result.minute == expected.minute
      assert result.second == expected.second
    end

    test "handles invalid date string" do
      assert DateTimeUtil.parse_datetime("not a date") == nil
    end

    test "handles malformed ISO 8601 string" do
      assert DateTimeUtil.parse_datetime("2023-02-30T25:70:99Z") == nil
    end

    test "handles non-string, non-DateTime values" do
      assert DateTimeUtil.parse_datetime(123) == nil
      assert DateTimeUtil.parse_datetime(%{}) == nil
      assert DateTimeUtil.parse_datetime([]) == nil
    end
  end
end
