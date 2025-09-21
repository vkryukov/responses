# Responses

A client library for the Responses API with automatic text extraction and cost calculation.

## Installation

Add `responses` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:responses, "~> 0.0.1"}
  ]
end
```

## Configuration

Set your OpenAI API key using one of these methods:

### Environment Variable
```bash
export OPENAI_API_KEY="your-api-key"
```

### Application Config
```elixir
config :responses, :openai_api_key, "your-api-key"
```

## Getting Started

For a comprehensive tutorial and examples, see the [interactive tutorial](tutorial.livemd) in Livebook.

## Advanced Examples

### Prompt Helpers

Use `Responses.Prompt` to safely compose message inputs and function outputs.

```elixir
alias Responses
alias Responses.Prompt

# Compose a prompt with roles
opts = %{}
opts = Prompt.add_developer(opts, "Talk like a pirate.")
opts = Prompt.add_user(opts, "Write me a haiku about Elixir")
opts = Map.put(opts, :model, "gpt-4.1-mini")

response = Responses.create!(opts)
IO.puts(response.text)

# Prepend a system message
opts = Prompt.prepend(opts, %{role: :system, content: "You are a helpful coach"})
followup = Responses.create!(opts)

# Handling function calls: execute and append outputs
functions = %{
  "get_time" => fn %{} -> DateTime.utc_now() |> to_string() end
}

{:ok, with_calls} = Responses.create(input: "What time is it?", tools: [
  Responses.Schema.build_function("get_time", "Get UTC time", %{})
], model: "gpt-4.1-mini")

opts = Prompt.add_function_outputs(%{input: []}, with_calls.function_calls, functions)
final = Responses.create!(with_calls, opts)
IO.puts(final.text)
```

### Simple terminal chat

```elixir
defmodule Chat do
  alias Responses

  def run do
    IO.puts("Simple AI Chat (type /exit or /quit to end)")
    IO.puts("=" |> String.duplicate(40))

    loop(nil)
  end

  defp loop(previous_response) do
    input = IO.gets("\nYou: ") |> String.trim()

    case input do
      cmd when cmd in ["/exit", "/quit"] ->
        IO.puts("\nGoodbye!")

      _ ->
        IO.write("\nAI: ")

        # Use previous response for context, or create new conversation
        response = if previous_response do
          # Continue conversation with context
          Responses.create!(
            previous_response,
            input: input,
            stream: Responses.Stream.delta(&IO.write/1)
          )
        else
            # First message - start new conversation
            Responses.create!(
              input: input,
              model: "gpt-4.1-mini",
              stream: Responses.Stream.delta(&IO.write/1)
            )
        end

        IO.puts("")  # Add newline after response
        loop(response)
    end
  end
end

# Run the chat
Chat.run()
```


### Streaming with Structured Output

```elixir
# Stream a JSON response with structured output
Responses.stream(
  input: "List 3 programming languages with their year of creation",
  model: "gpt-4.1-mini",
  schema: %{
    languages: {:array, %{
      name: :string,
      year: :integer,
      paradigm: {:string, description: "Main programming paradigm"}
    }}
  }
)
|> Responses.Stream.json_events()
|> Enum.each(&IO.puts/1)
```

### Array Schemas (New in 0.6.0)

Arrays can now be used directly at the root level of schema definitions:

```elixir
# Define an array schema at the root level
{:ok, response} = Responses.create(
  input: "List 3 interesting facts about space exploration",
  schema: {:array, %{
    fact: :string,
    year: {:integer, description: "Year of the event"},
    significance: {:string, description: "Why this fact is important"}
  }},
  model: "gpt-4.1-mini"
)

# The response.parsed will be an array directly:
# [
#   %{"fact" => "First satellite launch", "year" => 1957, "significance" => "Started the space age"},
#   %{"fact" => "Moon landing", "year" => 1969, "significance" => "First humans on another celestial body"},
#   %{"fact" => "ISS construction", "year" => 1998, "significance" => "Permanent human presence in space"}
# ]
```

The library automatically handles OpenAI's requirement that the root level must be an object by wrapping and unwrapping arrays transparently.

### Options Normalization, Text/Schema Merge, and Follow-up Preservation

- All public entry points (`create/1,2`, `stream/1`, `run/2`) accept maps or keyword lists with atom or string keys. Internally, the library normalizes options into string-keyed maps.
- When you pass a `schema`, it merges into `text` options instead of overwriting them. This means fields like `text.verbosity` are preserved while `text.format` is set to the generated JSON Schema for that single call.

- Follow-up preservation (create/2): only the following are preserved from the previous response unless overridden:
  - `model`
  - `reasoning.effort`
  - `text.verbosity`
  Text format/schema is never preserved between calls; specify a new `schema:` if you need structured output on a follow-up.

Example preserving `text` options:

```elixir
payload = Responses.Internal.prepare_payload(%{
  input: "test",
  text: %{verbosity: "low"},
  schema: %{name: :string},
  model: "gpt-4.1-mini"
})

# payload["text"]["verbosity"] == "low"
# payload["text"]["format"]["type"] == "json_schema"
```

For contributors: the codebase includes small helpers to merge additions into a named section (e.g., "text") and to preserve selected keys from a source map into options when missing.

### Cost Tracking with High Precision

```elixir
{:ok, response} = Responses.create(input: "Explain quantum computing", model: "gpt-4.1-mini")

# All cost values are Decimal for precision
IO.inspect(response.cost)
# => %{
#      input_cost: #Decimal<0.0004>,
#      output_cost: #Decimal<0.0008>,
#      total_cost: #Decimal<0.0012>,
#      cached_discount: #Decimal<0>
#    }

# Convert to float if needed
total_in_cents = response.cost.total_cost |> Decimal.mult(100) |> Decimal.to_float()
```

## Documentation

- [API Documentation](https://hexdocs.pm/responses)
- [Interactive Tutorial](tutorial.livemd)
- [GitHub Repository](https://github.com/vkryukov/openai-responses)
### Rehydrating a Response from a Map

Use `Responses.Response.from_map/1` to rebuild a `%Response{}` struct from a stored map (supports atom or string keys):

```elixir
alias Responses.Response

stored = %{
  "text" => "hello",
  "body" => %{"id" => "resp_123", "model" => "gpt-4.1-mini"},
  "cost" => %{"input_cost" => "0.0001", "output_cost" => 0.0, "total_cost" => 0.0001, "cached_discount" => 0}
}

response = Response.from_map(stored)
# => %Response{text: "hello", body: %{"id" => "resp_123", ...}, cost: %{...}}
```
