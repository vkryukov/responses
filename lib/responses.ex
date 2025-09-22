defmodule Responses do
  @moduledoc """
  Client for the Responses API.

  This module provides a simple interface for creating AI responses with support for:
  - Text and structured output generation
  - Streaming responses with Server-Sent Events (SSE)
  - Automatic cost calculation for all API calls
  - JSON Schema-based structured outputs

  ## Available Functions

  - `create/1` and `create/2` - Create AI responses (synchronous or streaming)
  - `create!/1` and `create!/2` - Same as create but raises on error
  - `run/2` and `run!/2` - Run conversations with automatic function calling
  - `stream/1` - Stream responses as an Enumerable
  - `list_models/0` and `list_models/1` - List available OpenAI models
  - `request/1` - Low-level API request function

  ## Configuration

  Set your OpenAI API key via:
  - Environment variable: `OPENAI_API_KEY`
  - Application config: `config :responses, :openai_api_key, "your-key"`

  ## Examples

  See the [tutorial](tutorial.livemd) for comprehensive examples and usage patterns.
  """

  @default_receive_timeout 60_000

  alias Responses
  alias Responses.Error
  alias Responses.Internal
  alias Responses.Options
  alias Responses.Provider
  alias Responses.Response

  @typedoc "User-facing options accepted by create/1, stream/1, run/2"
  @type options_input :: map() | keyword()

  @typedoc "Result from low-level request or create/1"
  @type result :: {:ok, Response.t()} | {:error, term()}

  @doc """
  Create a new response.

  When the argument is a string, it is used as the input text.
  Otherwise, the argument is expected to be a keyword list or map of options that OpenAI expects,
  such as `input`, `model`, `temperature`, `max_tokens`, etc.

  ## LLM Options Preservation with previous_response_id

  The OpenAI API always requires a model parameter, even when using `previous_response_id`.

  When using `create/1` with manual `previous_response_id`:
  - If no model is specified, the default model is used
  - LLM options (model, text, reasoning) from the previous response are NOT automatically inherited

  When using `create/2` with a Response object:
  - Only these options are preserved from the previous response:
    - `model`
    - `reasoning.effort`
    - `text.verbosity`
  - Text format/schema (`text.format` or `schema:` option) is never preserved; specify a new `schema:` if needed
  - You can override any preserved option by explicitly providing a value

      # Manual previous_response_id - uses defaults if not specified
      Responses.create(input: "Hello", previous_response_id: "resp_123")

      # Manual previous_response_id - with explicit options
      Responses.create(input: "Hello", previous_response_id: "resp_123", model: "gpt-4.1")

      # Using create/2 - automatically inherits LLM options from previous response
      Responses.create(previous_response, input: "Hello")

      # Using create/2 - with reasoning effort preserved (requires model that supports reasoning)
      first = Responses.create!(input: "Question", model: "gpt-5-mini", reasoning: %{effort: "high"})
      followup = Responses.create!(first, input: "Follow-up")  # Inherits gpt-5-mini and high reasoning

  ## Examples

      # Using a keyword list
      Responses.create(input: "Hello", model: "gpt-4.1", temperature: 0.7)

      # Using a map
      Responses.create(%{input: "Hello", model: "gpt-4.1", temperature: 0.7})

      # String shorthand
      Responses.create("Hello")

  ## Structured Output with :schema

  Pass a `schema:` option to get structured JSON output from the model.
  The schema is defined using a simple Elixir syntax that is converted to JSON Schema format.

  Both maps and keyword lists with atom or string keys are accepted for all options:

      # Using a map with atom keys
      Responses.create(%{
        input: "Extract user info from: John Doe, username @johndoe, john@example.com",
        schema: %{
          name: :string,
          username: {:string, pattern: "^@[a-zA-Z0-9_]+$"},
          email: {:string, format: "email"}
        }
      })

      # Using a keyword list
      Responses.create(
        input: "Extract product details",
        schema: [
          product_name: :string,
          price: :number,
          in_stock: :boolean,
          tags: {:array, :string}
        ]
      )

      # Arrays at the root level (new in 0.6.0)
      Responses.create(
        input: "List 3 US presidents with facts",
        schema: {:array, %{
          name: :string,
          birth_year: :integer,
          achievements: {:array, :string}
        }}
      )
      # Returns an array directly in response.parsed

      # Mixed keys (atoms and strings) are supported
      Responses.create(%{
        "input" => "Analyze this data",
        :schema => %{
          "result" => :string,
          :confidence => :number
        }
      })

  The response will include a `parsed` field with the extracted structured data.
  See `Responses.Schema` for the full schema syntax documentation.

  ## Streaming

  Pass a `stream:` option with a callback function to stream the response.
  The callback receives results wrapped in `{:ok, chunk}` or `{:error, reason}` tuples:

      Responses.create(
        input: "Write a story",
        stream: fn
          {:ok, %{event: "response.output_text.delta", data: %{"delta" => text}}} ->
            IO.write(text)
            :ok
          {:error, reason} ->
            IO.puts("Stream error: \#{inspect(reason)}")
            :ok  # Continue despite errors
          _ ->
            :ok
        end
      )

  The callback should return `:ok` to continue or `{:error, reason}` to stop the stream.

  For simpler text streaming, use the `delta/1` helper:

      Responses.create(
        input: "Write a story",
        stream: Responses.Stream.delta(&IO.write/1)
      )

  If no model is specified, the default model is used.
  """
  @spec create(options_input) :: result
  def create(options) when is_list(options) or is_map(options) do
    normalized = Options.normalize(options)
    {stream_callback, normalized} = Map.pop(normalized, "stream")

    result =
      if stream_callback do
        Responses.Stream.stream_with_callback(stream_callback, normalized)
      else
        {payload, provider} = build_request(normalized)

        request(
          provider: provider,
          url: "/responses",
          json: payload,
          method: :post
        )
      end

    with {:ok, response} <- result do
      {:ok, process_response(response)}
    end
  end

  def create(input) when is_binary(input) do
    IO.warn(
      "Passing a binary to Responses.create/1 is deprecated. Use create(input: \"...\") or options map/keyword."
    )

    create(input: input)
  end

  # Define exactly which options should be preserved across chained responses.
  # We only preserve:
  # - model name
  # - reasoning effort
  # - text verbosity
  # Note: We explicitly do NOT preserve any text.format/schema between calls.
  @preserved_llm_paths [["model"], ["reasoning", "effort"], ["text", "verbosity"]]

  @doc """
  Create a response based on a previous response.

  This allows creating follow-up responses that maintain context from a previous response.
  The previous response's ID is automatically included in the request.

  Options can be provided as either a keyword list or a map.

  ## Preserved Options

  The following options are automatically preserved from the previous response unless explicitly overridden:
  - `model` - The model used for generation
  - `text` - Text generation settings (including verbosity)
  - `reasoning` - Reasoning settings (including effort level)

  ## Examples

      {:ok, first} = Responses.create("What is Elixir?")

      # Using keyword list
      {:ok, followup} = Responses.create(first, input: "Tell me more about its concurrency model")

      # Using map
      {:ok, followup} = Responses.create(first, %{input: "Tell me more about its concurrency model"})

      # With reasoning effort preserved (requires model that supports reasoning)
      {:ok, first} = Responses.create(input: "Complex question", model: "gpt-5-mini", reasoning: %{effort: "high"})
      {:ok, followup} = Responses.create(first, input: "Follow-up")  # Inherits gpt-5-mini and high reasoning effort
  """
  @spec create(Response.t(), options_input) :: result
  def create(%Response{} = previous_response, options) when is_list(options) or is_map(options) do
    # Normalize to map with string keys for consistent handling
    options_map = Options.normalize(options)

    # Add previous_response_id
    options_map = Map.put(options_map, "previous_response_id", previous_response.body["id"])

    # Preserve LLM options from the previous response if not explicitly provided
    options_map = preserve_llm_options(options_map, previous_response.body)

    create(options_map)
  end

  # Helper to preserve selected LLM options from previous response
  defp preserve_llm_options(options_map, previous_body) do
    Options.preserve_paths(options_map, previous_body, @preserved_llm_paths)
  end

  @doc """
  Same as `create/1` but raises an error on failure.

  Returns the response directly instead of an {:ok, response} tuple.

  ## Examples

      response = Responses.create!("Hello, world!")
      IO.puts(response.text)
  """
  @spec create!(options_input) :: Response.t()
  def create!(options) do
    case create(options) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  @doc """
  Same as `create/2` but raises an error on failure.

  Returns the response directly instead of an {:ok, response} tuple.

  ## Examples

      first = Responses.create!("What is Elixir?")
      followup = Responses.create!(first, input: "Tell me more")
  """
  @spec create!(Response.t(), options_input) :: Response.t()
  def create!(%Response{} = previous_response, options) do
    case create(previous_response, options) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  @doc """
  Stream a response from the OpenAI API as an Enumerable.

  Returns a Stream that yields chunks with `event` and `data` keys.

  Options can be provided as either a keyword list or a map.

  ## Examples

      # Stream and handle all results
      for result <- Responses.stream("Tell me a story") do
        case result do
          {:ok, chunk} -> IO.inspect(chunk)
          {:error, reason} -> IO.puts("Error: \#{inspect(reason)}")
        end
      end

      # Process only text deltas, ignoring errors
      Responses.stream("Write a poem")
      |> Stream.filter(fn
        {:ok, %{event: "response.output_text.delta"}} -> true
        _ -> false
      end)
      |> Stream.map(fn {:ok, chunk} -> chunk.data["delta"] end)
      |> Enum.each(&IO.write/1)

      # Accumulate all text with error handling (using map)
      result = Responses.stream(%{input: "Explain quantum physics"})
               |> Enum.reduce(%{text: "", errors: []}, fn
                 {:ok, %{event: "response.output_text.delta", data: %{"delta" => delta}}}, acc ->
                   %{acc | text: acc.text <> delta}
                 {:error, reason}, acc ->
                   %{acc | errors: [reason | acc.errors]}
                 _, acc ->
                   acc
               end)
  """
  @spec stream(options_input | String.t()) :: Enumerable.t()
  def stream(options) when is_list(options) or is_map(options) do
    Responses.Stream.stream(options)
  end

  def stream(input) when is_binary(input) do
    IO.warn(
      "Passing a binary to Responses.stream/1 is deprecated. Use stream(input: \"...\") or options map/keyword."
    )

    stream(input: input)
  end

  @doc """
  List available models.

  Accepts an optional `match` string to filter by model ID.
  """
  @spec list_models(String.t()) :: [map()]
  def list_models(match \\ "") do
    provider = Provider.get!(:openai)

    {:ok, response} =
      request(
        provider: provider,
        url: "/models"
      )

    response.body["data"]
    |> Enum.filter(&(&1["id"] =~ match))
  end

  @doc """
  Run a conversation with automatic function calling.

  This function automates the process of handling function calls by repeatedly calling the
  provided functions and feeding their results back to the model until a final response
  without function calls is received.

  ## Parameters

  - `options` - Keyword list or map of options to pass to `create/1`
  - `functions` - A map or keyword list where:
    - Keys are function names (as atoms or strings)
    - Values are functions that accept the parsed arguments and return the result

  ## Returns

  Returns a list of all responses generated during the conversation, in chronological order.
  The last response in the list will be the final answer without function calls.

  ## Examples

      # Define available functions
      functions = %{
        "get_weather" => fn %{"location" => location} ->
          # Simulate weather API call
          "The weather in \#{location} is 72°F and sunny"
        end,
        "get_time" => fn %{} ->
          DateTime.utc_now() |> to_string()
        end
      }

      # Create function tools
      weather_tool = Responses.Schema.build_function(
        "get_weather",
        "Get current weather for a location",
        %{location: :string}
      )

      time_tool = Responses.Schema.build_function(
        "get_time",
        "Get the current UTC time",
        %{}
      )

      # Run the conversation (with keyword list)
      responses = Responses.run(
        [input: "What's the weather in Paris and what time is it?",
         tools: [weather_tool, time_tool]],
        functions
      )

      # Or with map
      responses = Responses.run(
        %{input: "What's the weather in Paris and what time is it?",
          tools: [weather_tool, time_tool]},
        functions
      )

      # The last response contains the final answer
      final_response = List.last(responses)
      IO.puts(final_response.text)
  """
  @spec run(options_input, map() | keyword()) :: [Response.t()] | {:error, term()}
  def run(options, functions)
      when is_list(options) and (is_map(functions) or is_list(functions)) do
    case do_run(options, functions, []) do
      responses when is_list(responses) -> Enum.reverse(responses)
      error -> error
    end
  end

  def run(options, functions)
      when is_map(options) and (is_map(functions) or is_list(functions)) do
    # Convert map to list for processing
    options_list = Map.to_list(options)
    run(options_list, functions)
  end

  defp do_run(options, functions, responses) do
    case create(options) do
      {:ok, response} ->
        handle_response(response, functions, responses)

      {:error, _} = error ->
        error
    end
  end

  defp do_run(%Response{} = previous_response, options, functions, responses) do
    case create(previous_response, options) do
      {:ok, response} ->
        handle_response(response, functions, responses)

      {:error, _} = error ->
        error
    end
  end

  defp handle_response(response, functions, responses) do
    responses = [response | responses]

    case response.function_calls do
      nil ->
        # No function calls, return all responses
        responses

      [] ->
        # Empty function calls, return all responses
        responses

      calls ->
        # Process function calls and continue
        outputs_opts =
          Responses.Prompt.add_function_outputs(%{input: []}, calls, functions)

        # Continue conversation with function results using the latest response
        do_run(response, Map.to_list(outputs_opts), functions, responses)
    end
  end

  @doc """
  Same as `run/2` but raises an error on failure.

  Returns the list of responses directly instead of an {:ok, responses} tuple.
  """
  @spec run!(options_input, map() | keyword()) :: [Response.t()]
  def run!(options, functions) do
    case run(options, functions) do
      responses when is_list(responses) -> responses
      {:error, reason} -> raise "Function calling failed: #{inspect(reason)}"
    end
  end

  @doc """
  Request a response from the OpenAI API.

  Used as a building block by other functions in this module.
  Accepts that same arguments as `Req.request/1`.
  You should provide `url`, `json`, `method`, and other options as needed.
  """
  @spec request(keyword() | map()) :: result
  def request(options) when is_list(options) do
    {provider, req_options} = Keyword.pop(options, :provider)
    provider = ensure_provider_struct(provider)

    req =
      Req.new(
        base_url: provider.base_url,
        receive_timeout: @default_receive_timeout
      )
      |> put_auth(provider)
      |> Req.merge(req_options)

    do_request(req, provider)
  end

  def request(%{} = options) do
    provider = Map.fetch!(options, :provider)
    rest = options |> Map.delete(:provider) |> Map.to_list()
    request([provider: provider] ++ rest)
  end

  # Process a response by extracting text, JSON, function calls, and calculating cost
  defp process_response(response) do
    response
    |> Response.extract_json()
    |> Response.extract_function_calls()
    |> Response.calculate_cost()
  end

  @doc false
  @spec build_request(map()) :: {map(), Provider.Info.t()}
  def build_request(options) when is_map(options) do
    payload = Internal.prepare_payload(options)
    {payload, provider} = Provider.assign_model(payload)
    Provider.warn_on_unsupported(provider, options)
    {payload, provider}
  end

  defp ensure_provider_struct(%Provider.Info{} = provider), do: provider

  defp ensure_provider_struct(nil),
    do: raise(ArgumentError, "Request options must include a :provider")

  defp ensure_provider_struct(identifier), do: Provider.get!(identifier)

  defp do_request(req, provider) do
    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, %Response{body: body, provider: provider}}

      {:ok, resp = %Req.Response{}} ->
        {:error, Error.from_response(resp)}

      {_status, other} ->
        {:error, other}
    end
  end

  defp put_auth(req, provider) do
    api_key = Provider.fetch_api_key(provider)
    Req.merge(req, auth: {:bearer, api_key})
  end
end
