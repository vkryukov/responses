defmodule Responses.Provider.XAI do
  @moduledoc """
  Provider definition for the xAI Responses-compatible API.
  """

  alias Responses.Provider.Info

  @default_base_url "https://api.x.ai/v1"

  @doc false
  @spec definition() :: Info.t()
  def definition do
    %Info{
      id: :xai,
      name: "xAI",
      base_url: resolve_base_url(),
      auth: %{
        config: [{:responses, :xai_api_key}],
        env: ["XAI_API_KEY"]
      },
      unsupported_options: [
        {[
           "instructions"
         ],
         "xAI does not yet support the `instructions` option. The request will be sent unchanged."},
        {[
           "reasoning",
           "effort"
         ], "xAI does not yet support reasoning effort. The request will be sent unchanged."}
      ]
    }
  end

  defp resolve_base_url do
    Application.get_env(:responses, :xai_base_url) ||
      System.get_env("XAI_BASE_URL") ||
      @default_base_url
  end
end
