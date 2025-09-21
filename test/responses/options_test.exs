defmodule OpenAI.Responses.OptionsTest do
  use ExUnit.Case, async: true

  alias OpenAI.Responses.Options

  describe "normalize/1" do
    test "normalizes keyword lists to string-key maps" do
      opts = Options.normalize(input: "hello", model: "gpt-4o", nested: [foo: 1, bar: 2])

      assert opts == %{
               "input" => "hello",
               "model" => "gpt-4o",
               "nested" => %{"foo" => 1, "bar" => 2}
             }
    end

    test "normalizes maps with atom and string keys" do
      opts = Options.normalize(%{"input" => "x", model: "gpt-4.1-mini"})
      assert opts["input"] == "x"
      assert opts["model"] == "gpt-4.1-mini"
      refute Map.has_key?(opts, :model)
    end

    test "preserves regular lists as arrays" do
      tools = [%{"type" => "function", "name" => "get_weather"}]
      opts = Options.normalize(input: "hi", tools: tools)

      assert is_list(opts["tools"]) and
               hd(opts["tools"]) == %{"type" => "function", "name" => "get_weather"}
    end

    test "supports list of string-key tuples" do
      opts = Options.normalize([{"input", "test"}, {"max_tokens", 10}])
      assert opts == %{"input" => "test", "max_tokens" => 10}
    end

    test "raises on invalid list entries" do
      assert_raise ArgumentError, fn -> Options.normalize([:foo, :bar]) end
    end

    test "deeply normalizes nested structures" do
      opts = Options.normalize(%{a: %{b: [%{c: :ok}, [d: 1]]}})
      assert opts == %{"a" => %{"b" => [%{"c" => :ok}, %{"d" => 1}]}}
    end
  end

  describe "stringify helpers" do
    test "stringify_keys_shallow converts only top-level keys" do
      m = Options.stringify_keys_shallow(%{a: %{b: 1}, c: 2})
      assert m == %{"a" => %{b: 1}, "c" => 2}
    end

    test "stringify_keys_deep converts nested keys" do
      m = Options.stringify_keys_deep(%{a: %{b: [%{c: 1}]}})
      assert m == %{"a" => %{"b" => [%{"c" => 1}]}}
    end
  end

  describe "merge_text/2 and preserve_from/3" do
    test "merge_text merges without dropping existing keys" do
      opts = %{"text" => %{"verbosity" => "low"}}
      merged = Options.merge_text(opts, %{"format" => %{type: "json_schema"}})
      assert merged["text"]["verbosity"] == "low"
      assert merged["text"]["format"]["type"] == "json_schema"
    end

    test "preserve_from copies only missing keys" do
      source = %{"model" => "gpt-4o", "text" => %{}}
      opts = %{"input" => "hi", "model" => "gpt-4.1-mini"}
      result = Options.preserve_from(opts, source, ["model", "text"])
      # model already present, should remain as in opts
      assert result["model"] == "gpt-4.1-mini"
      # text missing, copied from source
      assert result["text"] == %{}
    end
  end
end
