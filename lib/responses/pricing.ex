defmodule Responses.Pricing do
  @moduledoc """
  Pricing information for supported Responses providers.

  Prices are in USD per million tokens and stored as Decimal values for
  precision. Source data for OpenAI is from https://platform.openai.com/docs/pricing,
  last refreshed on 2025-06-03. Pricing for other providers is populated as it
  becomes available.
  """

  # Raw pricing grouped by provider before Decimal coercion
  openai_pricing_data = %{
    # gpt-4.1 models
    "gpt-4.1" => {2.00, 0.50, 8.00},
    "gpt-4.1-2025-04-14" => {2.00, 0.50, 8.00},

    # gpt-4.1-mini models
    "gpt-4.1-mini" => {0.40, 0.10, 1.60},
    "gpt-4.1-mini-2025-04-14" => {0.40, 0.10, 1.60},

    # gpt-4.1-nano models
    "gpt-4.1-nano" => {0.10, 0.025, 0.40},
    "gpt-4.1-nano-2025-04-14" => {0.10, 0.025, 0.40},

    # gpt-4.5-preview models
    "gpt-4.5-preview" => {75.00, 37.50, 150.00},
    "gpt-4.5-preview-2025-02-27" => {75.00, 37.50, 150.00},

    # gpt-4o models
    "gpt-4o" => {2.50, 1.25, 10.00},
    "gpt-4o-2024-08-06" => {2.50, 1.25, 10.00},
    "gpt-4o-2024-11-20" => {2.50, 1.25, 10.00},
    "gpt-4o-2024-05-13" => {5.00, nil, 15.00},

    # gpt-4o-audio-preview models
    "gpt-4o-audio-preview" => {2.50, nil, 10.00},
    "gpt-4o-audio-preview-2024-12-17" => {2.50, nil, 10.00},
    "gpt-4o-audio-preview-2025-06-03" => {2.50, nil, 10.00},
    "gpt-4o-audio-preview-2024-10-01" => {2.50, nil, 10.00},

    # gpt-4o-realtime-preview models
    "gpt-4o-realtime-preview" => {5.00, 2.50, 20.00},
    "gpt-4o-realtime-preview-2024-12-17" => {5.00, 2.50, 20.00},
    "gpt-4o-realtime-preview-2025-06-03" => {5.00, 2.50, 20.00},
    "gpt-4o-realtime-preview-2024-10-01" => {5.00, 2.50, 20.00},

    # gpt-4o-mini models
    "gpt-4o-mini" => {0.15, 0.075, 0.60},
    "gpt-4o-mini-2024-07-18" => {0.15, 0.075, 0.60},

    # gpt-4o-mini-audio-preview models
    "gpt-4o-mini-audio-preview" => {0.15, nil, 0.60},
    "gpt-4o-mini-audio-preview-2024-12-17" => {0.15, nil, 0.60},

    # gpt-4o-mini-realtime-preview models
    "gpt-4o-mini-realtime-preview" => {0.60, 0.30, 2.40},
    "gpt-4o-mini-realtime-preview-2024-12-17" => {0.60, 0.30, 2.40},

    # o1 models
    "o1" => {15.00, 7.50, 60.00},
    "o1-2024-12-17" => {15.00, 7.50, 60.00},
    "o1-preview-2024-09-12" => {15.00, 7.50, 60.00},

    # o1-pro models
    "o1-pro" => {150.00, nil, 600.00},
    "o1-pro-2025-03-19" => {150.00, nil, 600.00},

    # o3 models
    "o3" => {2.00, 0.50, 8.00},
    "o3-2025-04-16" => {2.00, 0.50, 8.00},

    # o3 pro models
    "o3-pro" => {20.00, nil, 80.00},
    "o3-pro-2025-06-10" => {20.00, nil, 80.00},

    # o4-mini models
    "o4-mini" => {1.10, 0.275, 4.40},
    "o4-mini-2025-04-16" => {1.10, 0.275, 4.40},

    # o3-mini models
    "o3-mini" => {1.10, 0.55, 4.40},
    "o3-mini-2025-01-31" => {1.10, 0.55, 4.40},

    # o1-mini models
    "o1-mini" => {1.10, 0.55, 4.40},
    "o1-mini-2024-09-12" => {1.10, 0.55, 4.40},

    # codex-mini-latest models
    "codex-mini-latest" => {1.50, 0.375, 6.00},

    # gpt-4o-mini-search-preview models
    "gpt-4o-mini-search-preview" => {0.15, nil, 0.60},
    "gpt-4o-mini-search-preview-2025-03-11" => {0.15, nil, 0.60},

    # gpt-4o-search-preview models
    "gpt-4o-search-preview" => {2.50, nil, 10.00},
    "gpt-4o-search-preview-2025-03-11" => {2.50, nil, 10.00},

    # computer-use-preview models
    "computer-use-preview" => {3.00, nil, 12.00},
    "computer-use-preview-2025-03-11" => {3.00, nil, 12.00},

    # gpt-image-1 models
    "gpt-image-1" => {5.00, 1.25, nil},

    # gpt-5 models
    "gpt-5" => {1.25, 0.125, 10.00},
    "gpt-5-2025-08-07" => {1.25, 0.125, 10.00},
    "gpt-5-chat-latest" => {1.25, 0.125, 10.00},

    # gpt-5-mini models
    "gpt-5-mini" => {0.25, 0.025, 2.00},
    "gpt-5-mini-2025-08-07" => {0.25, 0.025, 2.00},

    # gpt-5-nano models
    "gpt-5-nano" => {0.05, 0.005, 0.40},
    "gpt-5-nano-2025-08-07" => {0.05, 0.005, 0.40}
  }

  xai_pricing_data = %{
    "grok-code-fast-1" => {0.20, 0.02, 1.50},
    "grok-4-fast-reasoning" => {0.20, 0.05, 0.50},
    "grok-4-fast" => {0.20, 0.05, 0.50},
    "grok-4-fast-non-reasoning" => {0.20, 0.05, 0.50},
    "grok-4" => {3.00, 0.75, 15.00},
    "grok-4-0709" => {3.00, 0.75, 15.00},
    "grok-4-latest" => {3.00, 0.75, 15.00},
    "grok-3-mini" => {0.30, 0.075, 0.50},
    "grok-3" => {3.00, 0.75, 15.00}
  }

  pricing_data = %{
    openai: openai_pricing_data,
    xai: xai_pricing_data
  }

  decimal = fn
    nil -> nil
    value -> Decimal.new(to_string(value))
  end

  @pricing Enum.reduce(pricing_data, %{}, fn {provider, models}, acc ->
             models =
               models
               |> Enum.map(fn {model, {input, cached, output}} ->
                 {model,
                  %{
                    input: decimal.(input),
                    cached_input: decimal.(cached),
                    output: decimal.(output)
                  }}
               end)
               |> Map.new()

             Map.put(acc, provider, models)
           end)

  @doc """
  Get pricing information for a model. Returns `nil` when pricing data is unknown.
  """
  @spec get_pricing(String.t()) :: map() | nil
  def get_pricing(model) when is_binary(model) do
    Enum.find_value(@pricing, fn {_provider, models} -> Map.get(models, model) end)
  end

  @doc """
  Get pricing for a provider/model combination.
  """
  @spec get_pricing(atom(), String.t()) :: map() | nil
  def get_pricing(provider, model) when is_atom(provider) and is_binary(model) do
    @pricing
    |> Map.get(provider, %{})
    |> Map.get(model)
  end

  def get_pricing(_provider, _model), do: nil

  @doc """
  List models with pricing metadata for all providers.
  """
  @spec list_models() :: [String.t()]
  def list_models do
    @pricing
    |> Map.values()
    |> Enum.flat_map(&Map.keys/1)
  end

  @doc """
  List models with pricing metadata for a specific provider.
  """
  @spec list_models(atom()) :: [String.t()]
  def list_models(provider) when is_atom(provider) do
    @pricing
    |> Map.get(provider, %{})
    |> Map.keys()
  end
end
