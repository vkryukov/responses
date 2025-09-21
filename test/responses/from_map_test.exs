defmodule Responses.FromMapTest do
  use ExUnit.Case, async: true

  alias Responses.Response

  test "recreates struct from string-keyed map with decimals" do
    raw = %{
      "text" => "hello",
      "parsed" => %{"k" => "v"},
      "parse_error" => %{"json" => "oops"},
      "function_calls" => [%{"name" => "fn", "call_id" => "id", "arguments" => %{"a" => 1}}],
      "body" => %{"model" => "gpt-4.1-mini", "usage" => %{"input_tokens" => 1}},
      "cost" => %{
        "input_cost" => "0.1",
        "output_cost" => 0.2,
        "total_cost" => 0.3,
        "cached_discount" => 0
      }
    }

    r = Response.from_map(raw)

    assert %Response{} = r
    assert r.text == "hello"
    assert r.parsed == %{"k" => "v"}
    assert r.body["model"] == "gpt-4.1-mini"

    # Known parse_error keys promoted to atoms
    assert is_map(r.parse_error)
    assert r.parse_error[:json] == "oops"

    # Function calls preserved
    assert is_list(r.function_calls)
    assert length(r.function_calls) == 1
    fc = hd(r.function_calls)
    assert (Map.get(fc, :name) || Map.get(fc, "name")) == "fn"

    # Cost coerced to Decimal
    assert Decimal.equal?(r.cost.input_cost, Decimal.new("0.1"))
    assert Decimal.equal?(r.cost.output_cost, Decimal.from_float(0.2))
    assert Decimal.equal?(r.cost.total_cost, Decimal.from_float(0.3))
    assert Decimal.equal?(r.cost.cached_discount, Decimal.new(0))
  end

  test "handles atom-keyed map and missing fields" do
    raw = %{
      text: nil,
      parsed: nil,
      body: %{}
    }

    r = Response.from_map(raw)

    assert %Response{} = r
    assert r.text == nil
    assert r.parsed == nil
    assert r.parse_error == nil
    assert r.function_calls == nil
    assert r.cost == nil
    assert r.body == %{}
  end
end
