defmodule Responses.Provider do
  @moduledoc """
  Provider registry and model resolution for the Responses client.

  Providers expose their configuration via `Responses.Provider.Info` structs. The
  registry supports mapping user-supplied model identifiers to the correct provider
  and canonical model name, fetching API keys, and emitting provider-specific
  warnings for unsupported options.
  """

  alias __MODULE__.Info
  alias Responses.Provider.{OpenAI, XAI}

  @typedoc "Identifier used to reference a provider"
  @type id :: atom()

  defmodule Info do
    @moduledoc """
    Metadata describing a provider implementation.

    * `:id` - Atom identifier (e.g. `:openai`, `:xai`).
    * `:name` - Human readable provider name.
    * `:base_url` - Base URL for API requests.
    * `:auth` - Map defining where to load credentials (config + env).
    * `:unsupported_options` - List of option paths that should trigger warnings.
    """
    @enforce_keys [:id, :name, :base_url, :auth, :unsupported_options]
    defstruct [:id, :name, :base_url, :auth, :unsupported_options]

    @type t :: %__MODULE__{
            id: atom(),
            name: String.t(),
            base_url: String.t(),
            auth: %{optional(:env) => [String.t()], optional(:config) => list()},
            unsupported_options: [{[String.t()], String.t()}]
          }
  end

  @providers [OpenAI.definition(), XAI.definition()]

  @openai_prefixes ["gpt-", "o1", "o3", "o4"]
  @openai_exact []

  @xai_prefixes ["grok-"]

  @doc """
  Enumerate all registered providers.
  """
  @spec providers() :: [Info.t()]
  def providers, do: @providers

  @doc """
  Retrieve provider metadata by identifier.
  """
  @spec get(id() | String.t() | Info.t()) :: {:ok, Info.t()} | :error
  def get(%Info{} = info), do: {:ok, info}

  def get(identifier) when is_atom(identifier) do
    @providers
    |> Enum.find(&(&1.id == identifier))
    |> case do
      nil -> :error
      info -> {:ok, info}
    end
  end

  def get(identifier) when is_binary(identifier) do
    normalized = String.downcase(identifier)

    @providers
    |> Enum.find(fn info -> Atom.to_string(info.id) == normalized end)
    |> case do
      nil -> :error
      info -> {:ok, info}
    end
  end

  def get(_), do: :error

  @doc """
  Same as `get/1` but raises `ArgumentError` on failure.
  """
  @spec get!(id() | String.t() | Info.t()) :: Info.t()
  def get!(identifier) do
    case get(identifier) do
      {:ok, info} -> info
      :error -> raise ArgumentError, "Unknown provider identifier: #{inspect(identifier)}"
    end
  end

  @doc """
  Resolve the provider and canonical model ID for a user-supplied model string.

  Returns `{:ok, provider, canonical_model}` or `{:error, reason}` when the model
  cannot be resolved.
  """
  @spec resolve_model(String.t() | atom()) :: {:ok, Info.t(), String.t()} | {:error, term()}
  def resolve_model(model) when is_atom(model), do: resolve_model(Atom.to_string(model))

  def resolve_model(model) when is_binary(model) do
    case parse_model_identifier(model) do
      {:prefixed, provider_identifier, model_name} ->
        with {:ok, provider} <- get(provider_identifier) do
          {:ok, provider, model_name}
        else
          :error -> {:error, {:unknown_provider, provider_identifier}}
        end

      {:unprefixed, model_name} ->
        case infer_provider(model_name) do
          {:ok, provider} -> {:ok, provider, model_name}
          :error -> {:error, {:unknown_model, model_name}}
        end
    end
  end

  def resolve_model(_other), do: {:error, :invalid_model}

  @doc """
  Update the provided options with a canonical model and return its provider.

  Raises `ArgumentError` when the model cannot be resolved.
  """
  @spec assign_model(map()) :: {map(), Info.t()}
  def assign_model(%{"model" => model} = options) do
    case resolve_model(model) do
      {:ok, provider, canonical} ->
        {Map.put(options, "model", canonical), provider}

      {:error, {:unknown_model, name}} ->
        raise ArgumentError,
              "Unknown model '#{name}'. Provide a fully-qualified model or update to a supported model."

      {:error, {:unknown_provider, provider_identifier}} ->
        raise ArgumentError,
              "Unknown provider '#{provider_identifier}' in model identifier '#{model}'."

      {:error, :invalid_model} ->
        raise ArgumentError, "Invalid model identifier: #{inspect(model)}"
    end
  end

  def assign_model(_options) do
    raise ArgumentError, "Missing required \"model\" option"
  end

  @doc """
  Emit warnings for any options unsupported by the provider.
  """
  @spec warn_on_unsupported(Info.t(), map()) :: :ok
  def warn_on_unsupported(%Info{unsupported_options: []}, _options), do: :ok

  def warn_on_unsupported(%Info{unsupported_options: unsupported_paths}, options) do
    Enum.each(unsupported_paths, fn {path, message} ->
      if option_present?(options, path) do
        IO.warn(message)
      end
    end)

    :ok
  end

  @doc """
  Fetch the API key for a provider using its configured config/env sources.
  """
  @spec fetch_api_key(Info.t()) :: String.t()
  def fetch_api_key(%Info{auth: auth} = info) do
    configs = Map.get(auth, :config, [])
    env_vars = Map.get(auth, :env, [])

    configs
    |> fetch_from_configs()
    |> case do
      nil ->
        env_vars
        |> fetch_from_env()
        |> case do
          nil -> raise_missing_key_error(info, env_vars)
          value -> value
        end

      value ->
        value
    end
  end

  ## -- internal helpers -------------------------------------------------------

  defp fetch_from_configs([]), do: nil

  defp fetch_from_configs(configs) when is_list(configs) do
    Enum.find_value(configs, fn
      {:deprecated, app, key, message} ->
        case Application.get_env(app, key) do
          nil ->
            nil

          value ->
            IO.warn(message)
            value
        end

      {app, key} ->
        Application.get_env(app, key)

      other ->
        raise ArgumentError, "Invalid config entry #{inspect(other)}"
    end)
  end

  defp fetch_from_configs(_), do: nil

  defp fetch_from_env([]), do: nil

  defp fetch_from_env([var | rest]) do
    case System.get_env(var) do
      nil -> fetch_from_env(rest)
      "" -> fetch_from_env(rest)
      value -> value
    end
  end

  defp raise_missing_key_error(info, []),
    do: raise(KeyError, message: "Missing API key for provider #{info.name} (#{info.id}).")

  defp raise_missing_key_error(info, [preferred | _] = vars) do
    joined = Enum.join(vars, ", ")

    raise KeyError,
      message:
        "Missing API key for provider #{info.name} (#{info.id}). Set one of #{joined} in the environment or configure it via config. Example: export #{preferred}=..."
  end

  defp option_present?(options, path) do
    get_in(options, path) != nil
  end

  defp parse_model_identifier(model) do
    case String.split(model, ":", parts: 2) do
      [provider, rest] when rest != "" -> {:prefixed, provider, rest}
      _ -> {:unprefixed, model}
    end
  end

  defp infer_provider(model) do
    cond do
      matches_openai?(model) -> {:ok, get!(:openai)}
      matches_xai?(model) -> {:ok, get!(:xai)}
      true -> :error
    end
  end

  defp matches_openai?(model) do
    Enum.any?(@openai_prefixes, &String.starts_with?(model, &1)) or model in @openai_exact
  end

  defp matches_xai?(model) do
    Enum.any?(@xai_prefixes, &String.starts_with?(model, &1))
  end
end
