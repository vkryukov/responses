defmodule Responses.TestSupport.LiveApiCase do
  @moduledoc false

  @compile {:no_warn_undefined, ExUnit.SkipTest}

  alias Responses.Response

  @provider_env %{
    openai: "RESPONSES_TEST_OPENAI_MODEL",
    xai: "RESPONSES_TEST_XAI_MODEL"
  }

  @provider_config %{
    openai: {:responses, :openai_test_model},
    xai: {:responses, :xai_test_model}
  }

  @provider_configs %{
    openai: %{
      default_model: "openai:gpt-4.1-mini",
      alternate_model: "openai:gpt-4o-mini",
      small_model: "openai:gpt-4.1-mini",
      reasoning_model: "openai:gpt-5-mini",
      list_match: "gpt",
      invalid_model: "openai:non-existent-model-xyz",
      capabilities: [:structured_output, :reasoning]
    },
    xai: %{
      default_model: "xai:grok-4-fast-non-reasoning",
      alternate_model: "xai:grok-4-fast",
      small_model: "xai:grok-4-fast-non-reasoning",
      reasoning_model: "xai:grok-4-fast",
      list_match: "grok",
      invalid_model: "xai:invalid-model",
      capabilities: [:structured_output]
    }
  }

  @provider_key :responses_live_api_provider

  @doc """
  Returns the default model identifier to use for a given provider.

  The lookup order is:
    * explicit environment variable (`RESPONSES_TEST_<PROVIDER>_MODEL`)
    * application environment (`config :responses, :<provider>_test_model`)
    * built-in fallback in this module
  """
  @spec default_model(:openai | :xai) :: String.t()
  def default_model(provider) when provider in [:openai, :xai] do
    provider
    |> fetch_env_override()
    |> fallback_to_config(provider)
    |> fallback_to_default(provider)
  end

  defp fetch_env_override(provider) do
    @provider_env
    |> Map.fetch!(provider)
    |> System.get_env()
    |> presence()
  end

  defp fallback_to_config(nil, provider) do
    @provider_config
    |> Map.fetch!(provider)
    |> fetch_config()
  end

  defp fallback_to_config(value, _provider), do: value

  defp fetch_config({app, key}) do
    case Application.get_env(app, key) do
      nil -> nil
      value -> value
    end
  end

  defp fallback_to_default(nil, provider), do: config(provider).default_model
  defp fallback_to_default(value, _provider), do: value

  defp presence(""), do: nil
  defp presence(value), do: value

  @spec config(:openai | :xai) :: map()
  def config(provider) when provider in [:openai, :xai] do
    Map.fetch!(@provider_configs, provider)
  end

  @doc """
  Returns the configured model string for the given provider and key.
  """
  @spec model(:openai | :xai, :default | :alternate | :small | :reasoning) :: String.t()
  def model(provider, key)

  def model(provider, :default), do: default_model(provider)

  def model(provider, :alternate) do
    config(provider).alternate_model
  end

  def model(provider, :small) do
    config(provider).small_model
  end

  def model(provider, :reasoning) do
    config(provider).reasoning_model
  end

  @doc """
  Returns true if the provider supports the given capability.
  """
  @spec supports?(:openai | :xai, atom()) :: boolean()
  def supports?(provider, capability) when provider in [:openai, :xai] do
    capability in Map.get(config(provider), :capabilities, [])
  end

  @spec supports_all?(:openai | :xai, [atom()]) :: boolean()
  def supports_all?(provider, capabilities) do
    Enum.all?(capabilities, &supports?(provider, &1))
  end

  @doc """
  Returns the invalid model identifier for a provider.
  """
  @spec invalid_model(:openai | :xai) :: String.t()
  def invalid_model(provider) when provider in [:openai, :xai] do
    config(provider).invalid_model
  end

  @doc """
  Extracts the model identifier without the provider prefix.
  """
  @spec model_base(String.t()) :: String.t()
  def model_base(model) do
    model
    |> String.split(":", parts: 2)
    |> List.last()
  end

  @doc """
  Returns `true` if the given `actual` model string matches the expected
  provider-specific model identified by `key`.
  """
  @spec model_used?(String.t(), :openai | :xai, atom()) :: boolean()
  def model_used?(actual, provider, key)

  def model_used?(actual, provider, key) when is_binary(actual) do
    expected = model(provider, key)
    base = model_base(expected)
    String.contains?(actual, base)
  end

  def model_used?(_actual, _provider, _key), do: false

  @doc """
  Returns the provider(s) that should run live API tests.

  Controlled via `RESPONSES_LIVE_API` ("openai" | "xai" | "both" | "none" | comma list).
  Defaults to `[:openai]` when unset for backwards compatibility.

  Supported options:
    * `:only` / `:except` – restrict the provider list explicitly.
    * `:require` – capability (or list of capabilities) that a provider must
      support to be included, e.g. `require: [:reasoning]`.
  """
  @spec providers(Keyword.t()) :: [:openai | :xai]
  def providers(opts \\ []) do
    env_providers()
    |> filter_only(opts)
    |> filter_except(opts)
    |> filter_capabilities(opts)
  end

  defp env_providers do
    case System.get_env("RESPONSES_LIVE_API") do
      nil ->
        [:openai]

      "" ->
        [:openai]

      "both" ->
        [:openai, :xai]

      "openai" ->
        [:openai]

      "xai" ->
        [:xai]

      "none" ->
        []

      other ->
        other
        |> String.split([",", " "], trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.flat_map(fn
          "openai" -> [:openai]
          "xai" -> [:xai]
          _ -> []
        end)
        |> Enum.uniq()
    end
  end

  defp filter_only(providers, opts) do
    case Keyword.get(opts, :only) do
      nil -> providers
      only when is_list(only) -> Enum.filter(providers, &(&1 in only))
      only -> Enum.filter(providers, &(&1 == only))
    end
  end

  defp filter_except(providers, opts) do
    case Keyword.get(opts, :except) do
      nil -> providers
      except when is_list(except) -> Enum.reject(providers, &(&1 in except))
      except -> Enum.reject(providers, &(&1 == except))
    end
  end

  defp filter_capabilities(providers, opts) do
    requirements =
      opts
      |> Keyword.get(:require, [])
      |> List.wrap()

    case requirements do
      [] -> providers
      capabilities -> Enum.filter(providers, &supports_all?(&1, capabilities))
    end
  end

  @doc """
  Runs the supplied function for each selected provider. Raises `ExUnit.SkipTest`
  when no providers match the environment selection or capability requirements.
  """
  @spec run_for_each_provider((:openai | :xai -> any()), Keyword.t()) :: :ok
  def run_for_each_provider(fun, opts \\ []) when is_function(fun, 1) do
    providers = providers(opts)

    case providers do
      [] ->
        :skipped

      providers ->
        Enum.each(providers, fn provider ->
          previous = Process.put(@provider_key, provider)

          try do
            fun.(provider)
          after
            if previous do
              Process.put(@provider_key, previous)
            else
              Process.delete(@provider_key)
            end
          end
        end)
    end
  end

  @doc """
  Convenience wrapper that yields both provider and the provider-specific default
  model.
  """
  @spec run_with_default_model((:openai | :xai, String.t() -> any()), Keyword.t()) :: :ok
  def run_with_default_model(fun, opts \\ []) when is_function(fun, 2) do
    run_for_each_provider(
      fn provider ->
        fun.(provider, model(provider, :default))
      end,
      opts
    )
  end

  @doc """
  Prepare a response for reuse as context in a follow-up request.

  Removes fields that are not supported by the provider (e.g. `reasoning`).
  """
  @spec prepare_follow_up(Response.t(), :openai | :xai) :: Response.t()
  def prepare_follow_up(%Response{} = response, provider) do
    response
    |> maybe_drop_reasoning(provider)
  end

  defp maybe_drop_reasoning(%Response{} = response, provider) do
    if supports?(provider, :reasoning) do
      response
    else
      cleaned_body = Map.delete(response.body || %{}, "reasoning")
      %Response{response | body: cleaned_body}
    end
  end

  @doc """
  Returns the provider set for the current live test execution.
  """
  @spec current_provider() :: :openai | :xai
  def current_provider do
    Process.get(@provider_key) || raise "no live API provider set"
  end

  @doc """
  Returns the identifier used when filtering `Responses.list_models/2`.
  """
  @spec list_match(:openai | :xai) :: String.t()
  def list_match(provider) do
    config(provider).list_match
  end

  @doc """
  Returns the provider-specific tag used to filter live API tests.
  """
  @spec provider_tag(:openai | :xai) :: atom()
  def provider_tag(:openai), do: :openai_api
  def provider_tag(:xai), do: :xai_api

  @doc """
  Builds include filters from the `RESPONSES_LIVE_API` environment variable.

  Supported values:
    * `"openai"` – run only OpenAI live API tests
    * `"xai"` – run only xAI live API tests
    * `"both"` – run all live API tests
    * `"none"` or unset – skip live API tests (default)
  """
  @spec include_filters() :: keyword()
  def include_filters do
    case System.get_env("RESPONSES_LIVE_API") do
      "openai" -> [:api, :openai_api, provider: :openai]
      "xai" -> [:api, :xai_api, provider: :xai]
      "both" -> [:api, :openai_api, :xai_api]
      _ -> []
    end
  end
end
