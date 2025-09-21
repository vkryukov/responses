defmodule Responses.Response do
  @moduledoc """
  Represent a response from the OpenAI API.

  The `Response` struct contains the following fields:
  - `text`: The extracted text from the response body.
  - `parsed`: The parsed response body.
  - `parse_error`: A map containing error messages if parsing failed.
  - `function_calls`: An array of extracted function calls from the response.
  - `body`: The raw response body.
  - `cost`: The calculated cost of the response in USD.

  All of the functions in this module act like "plugs", meaning they take a response as input and return a modified response as output.

  The `extract_text/1` function extracts the text from the response body, updating the `text` field of the response.
  The `extract_json/1` function extracts the data from the response body if it is a structured response.
  The `extract_function_calls/1` function extracts function calls from the response body.
  The `calculate_cost/1` function calculates the cost of the response based on token usage and model pricing.
  """
  defstruct [:text, :parsed, :parse_error, :function_calls, :body, :cost]

  alias Responses.Pricing

  @typedoc "Structured representation of an OpenAI response"
  @type cost_t :: %{
          required(:input_cost) => Decimal.t(),
          required(:output_cost) => Decimal.t(),
          required(:total_cost) => Decimal.t(),
          required(:cached_discount) => Decimal.t()
        }

  @type t :: %__MODULE__{
          text: String.t() | nil,
          parsed: map() | list() | nil,
          parse_error: map() | nil,
          function_calls: list() | nil,
          body: map(),
          cost: cost_t | nil
        }

  @doc """
  Rebuild a `%Response{}` struct from a map.

  Accepts maps with atom or string keys (or a mix). Known fields are:
  - "text" / :text
  - "parsed" / :parsed
  - "parse_error" / :parse_error (supports string keys for known entries: "json", "function_calls")
  - "function_calls" / :function_calls
  - "body" / :body (defaults to `%{}` if missing)
  - "cost" / :cost (coerces numeric and string values to Decimal)

  Unknown keys are ignored. This is useful when loading a previously
  persisted response from storage and rehydrating it into a struct.
  """
  @spec from_map(map()) :: t()
  def from_map(%{} = data) do
    %__MODULE__{
      text: get_key(data, :text),
      parsed: get_key(data, :parsed),
      parse_error: normalize_parse_error(get_key(data, :parse_error)),
      function_calls: normalize_function_calls(get_key(data, :function_calls)),
      body: normalize_body(get_key(data, :body)),
      cost: normalize_cost(get_key(data, :cost))
    }
  end

  @doc """
  Extract the text from the response body.

  Only extracts text from the first assistant response to handle cases where
  the API returns duplicate assistant responses.
  """
  def extract_text(response) do
    if response.text == nil do
      text =
        response.body
        |> Map.get("output", [])
        |> extract_assistant_outputs()
        |> extract_text_content()
        |> Enum.join("\n")

      %{response | text: text}
    else
      response
    end
  end

  # -- Internal: from_map helpers -------------------------------------------------

  defp get_key(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp normalize_body(%{} = body), do: body
  defp normalize_body(_), do: %{}

  defp normalize_function_calls(list) when is_list(list), do: list
  defp normalize_function_calls(_), do: nil

  defp normalize_parse_error(nil), do: nil

  defp normalize_parse_error(%{} = err) do
    # Promote known string keys to atom keys without creating new atoms
    json_err = Map.get(err, :json) || Map.get(err, "json")
    fc_err = Map.get(err, :function_calls) || Map.get(err, "function_calls")

    # Avoid duplicate mixed keys when we add atom keys below
    err
    |> Map.drop(["json", "function_calls"])
    |> maybe_put(:json, json_err)
    |> maybe_put(:function_calls, fc_err)
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp normalize_cost(nil), do: nil

  defp normalize_cost(%{} = cost) do
    %{
      input_cost: cost |> fetch_cost(:input_cost),
      output_cost: cost |> fetch_cost(:output_cost),
      total_cost: cost |> fetch_cost(:total_cost),
      cached_discount: cost |> fetch_cost(:cached_discount)
    }
  end

  defp fetch_cost(map, key) do
    value = Map.get(map, key) || Map.get(map, Atom.to_string(key))
    to_decimal(value)
  end

  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(nil), do: Decimal.new(0)
  defp to_decimal(i) when is_integer(i), do: Decimal.new(i)
  defp to_decimal(f) when is_float(f), do: Decimal.from_float(f)

  defp to_decimal(s) when is_binary(s) do
    try do
      Decimal.new(s)
    rescue
      _ -> Decimal.new(0)
    end
  end

  defp to_decimal(other) do
    try do
      Decimal.new(other)
    rescue
      _ -> Decimal.new(0)
    end
  end

  defp extract_assistant_outputs(outputs) do
    Enum.filter(outputs, fn output -> output["role"] == "assistant" end)
    |> Enum.take(1)
  end

  defp extract_text_content(outputs) do
    Enum.flat_map(outputs, fn output ->
      output
      |> Map.get("content", [])
      |> Enum.filter(fn content -> content["type"] == "output_text" end)
      |> Enum.map(fn content -> content["text"] end)
    end)
  end

  @doc """
  Extract function calls from the response body.

  Function calls are extracted from the response.body["output"] array and transformed
  into a more convenient format with parsed arguments.
  """
  def extract_function_calls(response) do
    if response.function_calls == nil do
      function_calls =
        Map.get(response.body, "output", [])
        |> Enum.filter(fn output -> output["type"] == "function_call" end)
        |> Enum.map(&parse_function_call/1)
        |> Enum.reduce({[], []}, fn
          {:ok, call}, {calls, errors} -> {[call | calls], errors}
          {:error, error}, {calls, errors} -> {calls, [error | errors]}
        end)

      case function_calls do
        {calls, []} ->
          %{response | function_calls: Enum.reverse(calls)}

        {calls, errors} ->
          existing_errors = response.parse_error || %{}
          updated_errors = Map.put(existing_errors, :function_calls, Enum.reverse(errors))
          %{response | function_calls: Enum.reverse(calls), parse_error: updated_errors}
      end
    else
      response
    end
  end

  defp parse_function_call(output) do
    name = output["name"]
    call_id = output["call_id"]
    arguments_json = output["arguments"]

    case Jason.decode(arguments_json) do
      {:ok, arguments} ->
        {:ok, %{name: name, call_id: call_id, arguments: arguments}}

      {:error, %Jason.DecodeError{} = error} ->
        {:error, "Function call '#{name}' (#{call_id}): #{Exception.message(error)}"}
    end
  end

  @doc """
  Extract the data from the response body if it is a structured response.

  Automatically extracts the text from the response body if it is not already extracted.
  If the schema was originally an array at the root level, it will be automatically
  unwrapped from the temporary object wrapper.
  """
  def extract_json(response) do
    response = response |> extract_text()

    if structured_response?(response) do
      case Jason.decode(response.text) do
        {:ok, parsed} ->
          # Check if we need to unwrap an array that was wrapped for OpenAI compatibility
          parsed = maybe_unwrap_array(parsed, response)
          %{response | parsed: parsed}

        {:error, %Jason.DecodeError{} = error} ->
          existing_errors = response.parse_error || %{}
          updated_errors = Map.put(existing_errors, :json, Exception.message(error))
          %{response | parse_error: updated_errors}
      end
    else
      response
    end
  end

  defp structured_response?(response) do
    get_in(response.body, ["text", "format", "schema"]) != nil
  end

  defp maybe_unwrap_array(parsed, response) do
    # Check if the schema indicates this was a wrapped array
    schema = get_in(response.body, ["text", "format", "schema"])

    if schema && wrapped_array_schema?(schema) do
      # If it was wrapped, extract the items array
      Map.get(parsed, "items", parsed)
    else
      parsed
    end
  end

  defp wrapped_array_schema?(schema) do
    # Check if this is our special wrapped array structure:
    # An object with a single "items" property that contains an array
    properties = schema["properties"] || %{}
    required = schema["required"] || []

    Map.keys(properties) == ["items"] &&
      required == ["items"] &&
      get_in(properties, ["items", "type"]) == "array"
  end

  @doc """
  Calculate the cost of the response based on token usage and model pricing.

  Returns the response with the `cost` field updated with a map containing:
  - `input_cost`: Cost for input tokens in USD (as Decimal)
  - `output_cost`: Cost for output tokens in USD (as Decimal)
  - `total_cost`: Total cost in USD (as Decimal)
  - `cached_discount`: Amount saved from cached tokens in USD (as Decimal) (if applicable)

  If pricing information is not available for the model, or usage information
  is missing, the cost field will be set to zero for all cost categories.
  """
  def calculate_cost(response) do
    case get_cost_params(response.body) do
      {:ok, usage, pricing} ->
        cost = calculate_cost_from_usage(usage, pricing)
        %{response | cost: cost}

      :error ->
        # Return zero costs when pricing is not available
        %{
          response
          | cost: %{
              input_cost: Decimal.new(0),
              output_cost: Decimal.new(0),
              total_cost: Decimal.new(0),
              cached_discount: Decimal.new(0)
            }
        }
    end
  end

  defp get_cost_params(body) do
    with model when is_binary(model) <- Map.get(body, "model"),
         usage when is_map(usage) <- Map.get(body, "usage"),
         pricing when is_map(pricing) <- Pricing.get_pricing(model) do
      {:ok, usage, pricing}
    else
      _ -> :error
    end
  end

  defp calculate_cost_from_usage(usage, pricing) do
    input_tokens = Map.get(usage, "input_tokens", 0)
    output_tokens = Map.get(usage, "output_tokens", 0)
    cached_tokens = get_in(usage, ["input_tokens_details", "cached_tokens"]) || 0
    regular_input_tokens = input_tokens - cached_tokens

    # Helper to calculate cost for a number of tokens given a price per million
    calc = fn tokens, price_per_million ->
      if price_per_million && tokens > 0 do
        Decimal.mult(Decimal.div(Decimal.new(tokens), 1_000_000), price_per_million)
      else
        Decimal.new(0)
      end
    end

    regular_input_cost = calc.(regular_input_tokens, pricing.input)
    cached_input_cost = calc.(cached_tokens, pricing.cached_input || pricing.input)
    output_cost = calc.(output_tokens, pricing.output)
    input_cost = Decimal.add(regular_input_cost, cached_input_cost)

    cached_discount =
      if pricing.cached_input && pricing.input && cached_tokens > 0 do
        potential_cost = calc.(cached_tokens, pricing.input)
        Decimal.sub(potential_cost, cached_input_cost)
      else
        Decimal.new(0)
      end

    %{
      input_cost: input_cost,
      output_cost: output_cost,
      total_cost: Decimal.add(input_cost, output_cost),
      cached_discount: cached_discount
    }
  end
end
