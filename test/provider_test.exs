defmodule Responses.ProviderTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Responses
  alias Responses.Provider

  describe "assign_model/1" do
    test "resolves explicit provider:model identifiers" do
      {payload, provider} = Provider.assign_model(%{"model" => "openai:gpt-4.1"})
      assert payload["model"] == "gpt-4.1"
      assert provider.id == :openai
    end

    test "infers provider for well-known OpenAI models" do
      {payload, provider} = Provider.assign_model(%{"model" => "gpt-5"})
      assert payload["model"] == "gpt-5"
      assert provider.id == :openai

      {payload, provider} = Provider.assign_model(%{"model" => "o3"})
      assert payload["model"] == "o3"
      assert provider.id == :openai
    end

    test "infers provider for xAI grok models" do
      {payload, provider} = Provider.assign_model(%{"model" => "grok-3"})
      assert payload["model"] == "grok-3"
      assert provider.id == :xai
    end

    test "raises for unknown models" do
      assert_raise ArgumentError, fn ->
        Provider.assign_model(%{"model" => "mystery-model"})
      end
    end
  end

  describe "warn_on_unsupported/3" do
    test "warns for unsupported options by default" do
      {:ok, xai} = Provider.get(:xai)
      options = %{"instructions" => %{"foo" => "bar"}}

      output =
        capture_io(:stderr, fn ->
          Provider.warn_on_unsupported(xai, options, nil)
        end)

      assert output =~ "xAI does not yet support the `instructions` option"
    end

    test "respects per-call preference to ignore warnings" do
      {:ok, xai} = Provider.get(:xai)
      options = %{"instructions" => %{"foo" => "bar"}}

      output =
        capture_io(:stderr, fn ->
          Provider.warn_on_unsupported(xai, options, :ignore)
        end)

      assert output == ""
    end
  end

  describe "Responses.build_request/1" do
    test "warns by default for unsupported options" do
      options = %{"model" => "grok-3", "instructions" => %{"tips" => "be concise"}}

      output =
        capture_io(:stderr, fn ->
          {payload, provider} = Responses.build_request(options)
          refute Map.has_key?(payload, "provider_warnings")
          assert provider.id == :xai
        end)

      assert output =~ "xAI does not yet support the `instructions` option"
    end

    test "respects per-request provider_warnings override" do
      options = %{
        "model" => "grok-3",
        "instructions" => %{"tips" => "be concise"},
        "provider_warnings" => :ignore
      }

      output =
        capture_io(:stderr, fn ->
          {payload, _provider} = Responses.build_request(options)
          refute Map.has_key?(payload, "provider_warnings")
        end)

      assert output == ""
    end
  end
end
