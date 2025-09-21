defmodule Responses.Internal do
  @moduledoc false

  @default_model "gpt-4.1-mini"

  alias Responses.Options
  alias Responses.Schema

  @doc """
  Prepare the payload for API requests.
  Handles schema conversion and sets default model.
  """
  @spec prepare_payload(map | keyword) :: map
  def prepare_payload(options) do
    # Normalize everything to maps with string keys
    options = Options.normalize(options)

    {schema, options} = Map.pop(options, "schema")

    options =
      if schema do
        # Merge schema-produced format into existing text options without losing fields
        Options.merge_text(options, %{"format" => Schema.build_output(schema)})
      else
        options
      end

    # Warn if model is missing (default substitution is currently applied but will be removed)
    unless Map.has_key?(options, "model") do
      IO.warn(
        "No :model specified. Using default '#{@default_model}' is deprecated and will be removed in a future release. Please set :model explicitly."
      )
    end

    Map.put_new(options, "model", @default_model)
  end

  @doc """
  Get the API key from application config or environment variable.
  """
  @spec get_api_key() :: String.t()
  def get_api_key do
    case Application.get_env(:responses, :openai_api_key) do
      nil -> fetch_legacy_api_key()
      key -> key
    end
  end

  defp fetch_legacy_api_key do
    case Application.get_env(:openai_responses, :openai_api_key) do
      nil ->
        System.fetch_env!("OPENAI_API_KEY")

      key ->
        IO.warn(
          "Using :openai_responses for configuration is deprecated. Update to :responses before the next major release.",
          []
        )

        key
    end
  end
end
