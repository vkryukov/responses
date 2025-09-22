defmodule Responses.Provider.OpenAI do
  @moduledoc """
  Provider definition for the OpenAI Responses API.
  """

  alias Responses.Provider.Info

  @default_base_url "https://api.openai.com/v1"

  @doc false
  @spec definition() :: Info.t()
  def definition do
    %Info{
      id: :openai,
      name: "OpenAI",
      base_url: resolve_base_url(),
      auth: %{
        config: [
          {:responses, :openai_api_key},
          {:deprecated, :openai_responses, :openai_api_key,
           "Using :openai_responses for configuration is deprecated. Update to :responses before the next major release."}
        ],
        env: ["OPENAI_API_KEY"]
      },
      unsupported_options: []
    }
  end

  defp resolve_base_url do
    Application.get_env(:responses, :openai_base_url) ||
      System.get_env("OPENAI_BASE_URL") ||
      @default_base_url
  end
end
