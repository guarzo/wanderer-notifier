defmodule WandererNotifier.Shared.Utils.FormattingUtilsTest do
  use ExUnit.Case, async: true
  alias WandererNotifier.Shared.Utils.FormattingUtils

  describe "format_isk/2" do
    test "formats billions with default options" do
      assert FormattingUtils.format_isk(1_500_000_000) == "1.5B ISK"
      assert FormattingUtils.format_isk(25_750_000_000) == "25.8B ISK"
    end

    test "formats millions with default options" do
      assert FormattingUtils.format_isk(1_500_000) == "1.5M ISK"
      assert FormattingUtils.format_isk(999_999) == "1000.0K ISK"
    end

    test "formats thousands with default options" do
      assert FormattingUtils.format_isk(1_500) == "1.5K ISK"
      assert FormattingUtils.format_isk(50_000) == "50.0K ISK"
    end

    test "formats small values" do
      assert FormattingUtils.format_isk(999) == "999 ISK"
      assert FormattingUtils.format_isk(1) == "1 ISK"
      assert FormattingUtils.format_isk(0) == "0 ISK"
    end

    test "respects precision option" do
      assert FormattingUtils.format_isk(1_567_890_000, precision: 0) == "2B ISK"
      assert FormattingUtils.format_isk(1_567_890_000, precision: 2) == "1.57B ISK"
      assert FormattingUtils.format_isk(1_567_890_000, precision: 3) == "1.568B ISK"
    end

    test "respects suffix option" do
      assert FormattingUtils.format_isk(1_500_000_000, suffix: false) == "1.5B"
      assert FormattingUtils.format_isk(1_500_000, suffix: false) == "1.5M"
      assert FormattingUtils.format_isk(999, suffix: false) == "999"
    end

    test "respects format option" do
      assert FormattingUtils.format_isk(1_234_567_890, format: :long) == "1,234,567,890 ISK"
      assert FormattingUtils.format_isk(999, format: :long) == "999 ISK"
    end

    test "handles float values" do
      assert FormattingUtils.format_isk(1_500_000_000.5) == "1.5B ISK"
      assert FormattingUtils.format_isk(999.99) == "1000 ISK"
    end
  end

  describe "format_isk_short/1" do
    test "formats with ISK suffix" do
      assert FormattingUtils.format_isk_short(2_500_000_000) == "2.5B ISK"
      assert FormattingUtils.format_isk_short(100_000) == "100.0K ISK"
    end
  end

  describe "format_isk_no_suffix/1" do
    test "formats without ISK suffix" do
      assert FormattingUtils.format_isk_no_suffix(2_500_000_000) == "2.5B"
      assert FormattingUtils.format_isk_no_suffix(100_000) == "100.0K"
    end
  end

  describe "format_isk_full/1" do
    test "formats with comma separators" do
      assert FormattingUtils.format_isk_full(2_500_000_000) == "2,500,000,000 ISK"
      assert FormattingUtils.format_isk_full(1_234) == "1,234 ISK"
    end
  end

  describe "format_number/1" do
    test "formats integers with commas" do
      assert FormattingUtils.format_number(1_234_567) == "1,234,567"
      assert FormattingUtils.format_number(999) == "999"
      assert FormattingUtils.format_number(1_000) == "1,000"
    end

    test "formats floats with commas" do
      assert FormattingUtils.format_number(1_234_567.89) == "1,234,567.89"
      assert FormattingUtils.format_number(999.5) == "999.5"
    end
  end

  describe "format_percentage/2" do
    test "formats percentages with default precision" do
      assert FormattingUtils.format_percentage(0.756) == "75.6%"
      assert FormattingUtils.format_percentage(0.5) == "50.0%"
      assert FormattingUtils.format_percentage(1.0) == "100.0%"
    end

    test "respects precision option" do
      assert FormattingUtils.format_percentage(0.756, precision: 0) == "76%"
      assert FormattingUtils.format_percentage(0.756, precision: 2) == "75.60%"
      assert FormattingUtils.format_percentage(0.12345, precision: 3) == "12.345%"
    end

    test "handles edge cases" do
      assert FormattingUtils.format_percentage(0) == "0.0%"
      assert FormattingUtils.format_percentage(0.001) == "0.1%"
      assert FormattingUtils.format_percentage(10.5) == "1050.0%"
    end
  end
end
