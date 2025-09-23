# Responses Usage Guide

This guide covers all public-facing functions of the Responses package for LLM agents. Responses is an Elixir client library for interacting with OpenAI's Large Language Models (LLMs), providing a simple and powerful interface for AI-powered text generation, structured outputs, function calling, and real-time streaming.

## Setup

```elixir
# Add to mix.exs
{:responses, "~> 0.1.2"}

# Set API keys via environment variables (only the providers you use are required)
export OPENAI_API_KEY="your-openai-key"
export XAI_API_KEY="your-xai-key"

# Optional: configure in your config files instead
config :responses, :openai_api_key, System.fetch_env!("OPENAI_API_KEY")
config :responses, :xai_api_key, System.fetch_env!("XAI_API_KEY")
```

### Selecting models & providers

- Use `provider:model` to address a specific provider explicitly, e.g. `"openai:gpt-4.1"` or `"xai:grok-3"`.
- For common OpenAI and xAI models you can omit the prefix; the library infers the provider using the following heuristics:
  - `gpt-*`, `o1*`, `o3*`, `o4-mini*` map to OpenAI.
  - `grok-*` maps to xAI.
- Unknown or ambiguous models raise an `ArgumentError` so you can address new models explicitly.
- To silence provider capability warnings on a single request pass `provider_warnings: :ignore`; set
  `config :responses, :provider_warning_mode, :ignore` to silence them globally.

## Main Module: Responses

### create/1 and create!/1
Creates a new AI response. The bang version raises on error.

```elixir
# Simple text input
{:ok, response} = Responses.create(input: "Write a haiku", model: "gpt-4.1-mini")
response = Responses.create!(input: "Write a haiku", model: "gpt-4.1-mini")

# With options
{:ok, response} = Responses.create(
  input: "Explain quantum physics",
  model: "gpt-4.1-mini",
  temperature: 0.7,
  max_tokens: 500
)

# Target xAI explicitly
{:ok, response} = Responses.create(
  input: "Summarise the latest xAI blog post",
  model: "xai:grok-3"
)

# Streaming text from xAI while silencing unsupported option warnings
Responses.create(
  input: "List three takeaways about Grok-4",
  model: "xai:grok-4-fast",
  stream: Responses.Stream.delta(&IO.write/1),
  provider_warnings: :ignore
)

# With structured output
response = Responses.create!(
  input: "List 3 facts",
  model: "gpt-4.1-mini",
  schema: %{facts: {:array, :string}}
)
response.parsed # => %{"facts" => ["fact1", "fact2", "fact3"]}

# With streaming callback
Responses.create(
  input: "Tell a story",
  model: "gpt-4.1-mini",
  stream: fn
    {:ok, %{event: "response.output_text.delta", data: %{"delta" => text}}} ->
      IO.write(text)
      :ok
    _ -> :ok
  end
)
```

### create/2 and create!/2
Creates follow-up responses maintaining conversation state on the OpenAI side. Only specific generation settings are preserved.

```elixir
first = Responses.create!(input: "What is Elixir?", model: "gpt-4.1-mini")
followup = Responses.create!(first, input: "Tell me more about its concurrency")

# Preservation rules for follow-ups:
# - Preserved: model, reasoning.effort, text.verbosity
# - Not preserved: text.format (schema) and any other options
#   If you need structured output on a follow-up, pass schema: ... explicitly.
# - When a provider marks one of the preserved options as unsupported (e.g. xAI and reasoning
#   effort), the library automatically drops that field before sending the follow-up request.

# Note: Passing a bare binary to `create/1` or `stream/1` is deprecated.
# Always pass options with `input: ...` and an explicit `model`.
```

### stream/1
Returns an Enumerable stream of response chunks.

```elixir
# Stream text content
text = Responses.stream(input: "Write a poem", model: "gpt-4.1-mini")
       |> Responses.Stream.text_deltas()
       |> Enum.join()

# Process stream with error handling
Responses.stream(input: "Generate data", model: "gpt-4.1-mini")
|> Enum.each(fn
  {:ok, chunk} -> IO.inspect(chunk)
  {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
end)
```

### run/2 and run!/2
Automates function calling by repeatedly calling functions until completion.

```elixir
# Define functions
functions = %{
  "get_weather" => fn %{"location" => loc} ->
    "15°C in #{loc}"
  end
}

# Define tools
weather_tool = Responses.Schema.build_function(
  "get_weather",
  "Get weather for a location",
  %{location: :string}
)

# Run conversation
responses = Responses.run(
  [input: "What's the weather in Paris?", tools: [weather_tool], model: "gpt-4.1-mini"],
  functions
)

# Last response has final answer
final_answer = List.last(responses).text
```

### add_function_outputs/3 (Prompt)
Executes function calls from a response and appends formatted results to `input`.

```elixir
# Get a response with function calls
{:ok, response} = Responses.create(
  input: "What's the weather in Paris?",
  tools: [weather_tool],
  model: "gpt-4.1-mini"
)

# Define function implementations
functions = %{
  "get_weather" => fn %{"location" => loc} ->
    # Custom logic before/after the actual call
    result = fetch_weather_data(loc)
    log_api_call(:weather, loc)
    # Result must be JSON-encodable (map, list, string, number, boolean, nil)
    %{temperature: result.temp, unit: "C", conditions: result.conditions}
  end
}

alias Responses.Prompt

# Execute functions and append outputs to the prompt
opts = Prompt.add_function_outputs(%{input: []}, response.function_calls, functions)

# Continue conversation with custom context or extra messages
{:ok, final} = Responses.create(response,
  Prompt.append(opts, %{role: :user, content: "Convert to Fahrenheit"})
)
```

### list_models/1 and list_models/2
Lists available models for a specific provider with optional filtering.

```elixir
# List all OpenAI models
models = Responses.list_models(:openai)

# Filter xAI models by pattern
grok_models = Responses.list_models(:xai, "grok-4")

# Inspect the raw payload returned by xAI
{:ok, raw} = Responses.request(provider: Responses.Provider.get!(:xai), url: "/models", method: :get)
```

### request/1
Low-level API request function for custom endpoints.

```elixir
{:ok, response} = Responses.request(
  url: "/models",
  method: :get
)

# Override the provider when hitting xAI endpoints
{:ok, response} = Responses.request(
  provider: Responses.Provider.get!(:xai),
  url: "/models",
  method: :get
)

# Suppress provider warnings for a single call
{:ok, response} = Responses.create(
  input: "Tell me a joke",
  model: "grok-3",
  provider_warnings: :ignore
)
```

## Response Module: Responses.Response

Response struct fields:
- `text` - Extracted assistant message text
- `parsed` - Parsed JSON for structured outputs
- `parse_error` - Parsing error details if any
- `function_calls` - Extracted function calls
- `body` - Raw API response body
- `cost` - Usage cost breakdown

### from_map/1
Rebuilds a `%Response{}` struct from a map with atom or string keys. Useful for rehydrating stored responses.

```elixir
alias Responses.Response

stored = %{
  "text" => "hello",
  "body" => %{"id" => "resp_123", "model" => "gpt-4.1-mini"},
  "cost" => %{
    "input_cost" => "0.0001",
    "output_cost" => 0.0,
    "total_cost" => 0.0001,
    "cached_discount" => 0
  }
}

response = Response.from_map(stored)
```

### extract_text/1
Extracts assistant messages from response. Automatically called by create functions.

```elixir
response = Response.extract_text(response)
IO.puts(response.text)
```

### extract_json/1
Extracts structured data from JSON responses. Automatically called for structured outputs.

```elixir
response = Response.extract_json(response)
data = response.parsed # => %{"key" => "value"}
```

### extract_function_calls/1
Extracts and parses function calls. Automatically called by create functions.

```elixir
response = Response.extract_function_calls(response)
calls = response.function_calls
# => [%{name: "get_weather", call_id: "...", arguments: %{"location" => "Paris"}}]
```

### calculate_cost/1
Calculates token usage costs. Automatically called by create functions.

```elixir
response = Response.calculate_cost(response)
response.cost # => %{
#   input_cost: #Decimal<0.0001>,
#   output_cost: #Decimal<0.0002>,
#   total_cost: #Decimal<0.0003>,
#   cached_discount: #Decimal<0.0000>
# }
```

## Stream Module: Responses.Stream

### stream_with_callback/2
Streams responses with a callback function, returns final response.

```elixir
{:ok, response} = Stream.stream_with_callback(
  fn
    {:ok, %{event: "response.output_text.delta", data: %{"delta" => text}}} ->
      IO.write(text)
      :ok
    {:error, reason} ->
      IO.puts("Error: #{inspect(reason)}")
      :ok
    _ -> :ok
  end,
  input: "Write a story",
  model: "gpt-4.1-mini"
)
```

### stream/1
Returns an Enumerable stream for flexible processing.

```elixir
stream = Stream.stream(input: "Generate content", model: "gpt-4.1-mini")
# Each item is {:ok, chunk} or {:error, reason}
```

### delta/1
Helper for creating simple text streaming callbacks.

```elixir
Responses.create(
  input: "Write a story",
  model: "gpt-4.1-mini",
  stream: Stream.delta(&IO.write/1)
)
```

### text_deltas/1
Extracts only text deltas from event stream.

```elixir
text = Responses.stream(input: "Write a poem", model: "gpt-4.1-mini")
       |> Stream.text_deltas()
       |> Enum.join()
```

### json_events/1
Converts stream to JSON parsing events for incremental processing.

```elixir
Responses.stream(
  input: "Generate JSON data",
  schema: %{items: {:array, %{name: :string}}},
  model: "gpt-4.1-mini"
)
|> Stream.json_events()
|> Enum.each(&IO.inspect/1)
# Yields: :start_object, {:string, "items"}, :colon, :start_array, etc.
```

## Schema Module: Responses.Schema

### build_output/1
Converts Elixir syntax to JSON Schema for structured outputs.

```elixir
# Simple types
schema = Schema.build_output(%{
  name: :string,
  age: :integer,
  active: :boolean
})

# With constraints
schema = Schema.build_output(%{
  email: {:string, format: "email"},
  username: {:string, pattern: "^[a-z]+$", min_length: 3},
  score: {:number, minimum: 0, maximum: 100}
})

# Arrays and nested objects
schema = Schema.build_output(%{
  tags: {:array, :string},
  addresses: {:array, %{
    street: :string,
    city: :string,
    country: :string
  }}
})

# Union types
schema = Schema.build_output(%{
  result: {:anyOf, [:string, :number, :boolean]}
})

# Arrays at the root level (automatic wrapping)
{:ok, response} = Responses.create(
  input: "List 3 US presidents",
  schema: {:array, %{
    name: :string,
    birth_year: :integer,
    facts: {:array, :string}
  }},
  model: "gpt-4.1-mini"
)
# response.parsed is a list (the library wraps/unpacks automatically)
```

### build_function/3
Creates function tool definitions for function calling.

```elixir
tool = Schema.build_function(
  "search_products",
  "Search for products by name and category",
  %{
    query: {:string, description: "Search query"},
    category: {:string, enum: ["electronics", "books", "clothing"]},
    max_results: {:integer, minimum: 1, maximum: 100, description: "Max results to return"}
  }
)

# Use with create
response = Responses.create!(
  input: "Find me some laptops",
  tools: [tool],
  model: "gpt-4.1-mini"
)
```

## Common Patterns

### Conversation with State
```elixir
# Initial response sets context
chat = Responses.create!(
  input: [
    %{role: :developer, content: "You are a helpful assistant"},
    %{role: :user, content: "Hello!"}
  ],
  model: "gpt-4.1-mini"
)

# Follow-ups maintain context
chat = Responses.create!(chat, input: "What can you help with?")
```

### Prompt.append/2 with a list of messages
```elixir
alias Responses.Prompt

opts = %{}
opts = Prompt.append(opts, [
  %{role: :developer, content: "Talk like a pirate."},
  "Write me a haiku about Elixir"
])

response = Responses.create!(opts)
IO.puts(response.text)

## Prompt Normalization Notes
- Prompt helpers (`append/2`, `prepend/2`, `add_user/2`, `add_developer/2`, `add_system/2`) always normalize `:input` to a list of message maps.
- Strings are converted to `%{role: :user, content: string}`.
- A single message map is wrapped in a list; `:input` is never a single map.
- When routing to xAI models, any `role: :developer` messages are converted to `:system` and emit a warning unless provider warnings are disabled (`provider_warnings: :ignore`).
```

### Structured Data Extraction
```elixir
response = Responses.create!(
  input: "Extract contact info from: John Doe, john@example.com, +1-555-0123",
  schema: %{
    name: :string,
    email: {:string, format: "email"},
    phone: {:string, pattern: "^\\+\\d{1,3}-\\d{3}-\\d{4}$"}
  },
  model: "gpt-4.1-mini"
)

contact = response.parsed
```

### Streaming with Progress
```elixir
Responses.stream(input: "Generate a long report", model: "gpt-4.1-mini")
|> Stream.with_index()
|> Stream.each(fn
  {{:ok, %{event: "response.output_text.delta", data: %{"delta" => text}}}, _i} ->
    IO.write(text)
  {{:ok, %{event: "response.completed"}}, _i} ->
    IO.puts("\n✓ Complete")
  _ -> nil
end)
|> Stream.run()
```

### Error Handling
```elixir
case Responses.create(input: "Generate content", model: "gpt-4.1-mini") do
  {:ok, response} ->
    IO.puts(response.text)
    IO.puts("Cost: $#{response.cost.total_cost}")
  {:error, %{"message" => msg}} ->
    IO.puts("API Error: #{msg}")
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Key Points

- Always provide a model explicitly
- All responses include automatic cost calculation
- Text extraction is idempotent (safe to call multiple times)
- Streaming callbacks should return `:ok` to continue or `{:error, reason}` to stop
- Function calling with `run/2` handles multiple rounds automatically
- Use `Prompt.add_function_outputs/3` for manual control over function execution
- Function outputs must be JSON-encodable (no tuples, atoms except true/false/nil)
- Structured outputs guarantee exact schema compliance
- Use `!` versions for simpler code when errors should crash
- Passing a bare binary to `create/1` or `stream/1` is deprecated; use `input: ...`
- Prompt helpers ensure `:input` is always a list of messages
