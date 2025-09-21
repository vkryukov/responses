defmodule OpenAI.Responses.OptionsPreservePathsTest do
  use ExUnit.Case, async: true

  alias OpenAI.Responses.Options

  @paths [["model"], ["reasoning", "effort"], ["text", "verbosity"]]

  test "preserve_paths copies only specified nested keys" do
    options = %{}

    source = %{
      "model" => "gpt-4o",
      "reasoning" => %{"effort" => "high", "other" => "ignored"},
      "text" => %{"verbosity" => "low", "format" => %{type: "json_schema"}, "other" => true},
      "unrelated" => 123
    }

    result = Options.preserve_paths(options, source, @paths)

    assert result["model"] == "gpt-4o"
    assert get_in(result, ["reasoning", "effort"]) == "high"
    assert get_in(result, ["text", "verbosity"]) == "low"

    # Ensure we didn't copy unrelated or sibling keys
    refute Map.has_key?(result, "unrelated")
    refute get_in(result, ["reasoning", "other"]) == "ignored"
    refute get_in(result, ["text", "other"]) == true
    # schema/format must not be preserved
    refute get_in(result, ["text", "format"])
  end

  test "preserve_paths does not overwrite existing values" do
    options = %{
      "model" => "gpt-4.1-mini",
      "reasoning" => %{"effort" => "low"},
      "text" => %{"verbosity" => "high"}
    }

    source = %{
      "model" => "gpt-4o",
      "reasoning" => %{"effort" => "high"},
      "text" => %{"verbosity" => "low"}
    }

    result = Options.preserve_paths(options, source, @paths)

    # Existing values remain unchanged
    assert result["model"] == "gpt-4.1-mini"
    assert get_in(result, ["reasoning", "effort"]) == "low"
    assert get_in(result, ["text", "verbosity"]) == "high"
  end

  test "preserve_paths fills nested value when container map exists" do
    options = %{"reasoning" => %{}, "text" => %{"verbosity" => nil}}
    source = %{"reasoning" => %{"effort" => "medium"}, "text" => %{"verbosity" => "low"}}

    result = Options.preserve_paths(options, source, @paths)

    assert get_in(result, ["reasoning", "effort"]) == "medium"
    assert get_in(result, ["text", "verbosity"]) == "low"
  end
end
