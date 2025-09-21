defmodule Responses.Prompt do
  @moduledoc """
  Helpers for composing and normalizing the `input` option for Responses.

  These helpers are pure and return a new options map. They do not enforce
  any domain policy or deduplicate messages; they only help safely compose
  inputs and execute function outputs.

  All helpers normalize `:input` to a list of message maps. When strings are
  provided (either as the whole input or individual items), they are converted
  to `%{role: :user, content: string}` messages. The `:input` option is never
  set to a single map — even a single message is wrapped in a list.
  """

  alias Responses.Options

  @type opts :: map() | keyword()

  @doc """
  Append message(s) to `opts.input`.

  Accepts a binary, a `%{role, content}` map, or a list of such values.
  Returns a new options map with `:input` normalized to a list of message maps.
  """
  @spec append(opts, binary | map() | [binary | map()]) :: map()
  def append(opts, messages) do
    opts = normalize_opts(opts)
    existing_raw = Map.get(opts, :input) || Map.get(opts, "input")
    new_msgs = normalize_messages(messages)

    case existing_raw do
      nil ->
        # Start a new list even for a single message
        Map.put(opts, :input, new_msgs)

      existing when not is_list(existing) ->
        existing_list = normalize_input(existing)
        Map.put(opts, :input, existing_list ++ new_msgs)

      existing when is_list(existing) ->
        existing_list = normalize_input(existing)
        Map.put(opts, :input, existing_list ++ new_msgs)
    end
  end

  @doc """
  Prepend message(s) to `opts.input`.

  Same accepted inputs and return shape as `append/2`.
  """
  @spec prepend(opts, binary | map() | [binary | map()]) :: map()
  def prepend(opts, messages) do
    opts = normalize_opts(opts)
    existing_raw = Map.get(opts, :input) || Map.get(opts, "input")
    new_msgs = normalize_messages(messages)

    case existing_raw do
      nil ->
        # Start a new list even for a single message
        Map.put(opts, :input, new_msgs)

      existing when not is_list(existing) ->
        existing_list = normalize_input(existing)
        Map.put(opts, :input, new_msgs ++ existing_list)

      existing when is_list(existing) ->
        existing_list = normalize_input(existing)
        Map.put(opts, :input, new_msgs ++ existing_list)
    end
  end

  @doc """
  Shorthand to append a user message.
  """
  @spec add_user(opts, binary) :: map()
  def add_user(opts, content) when is_binary(content) do
    append(opts, %{role: :user, content: content})
  end

  @doc """
  Shorthand to append a developer message.
  """
  @spec add_developer(opts, binary) :: map()
  def add_developer(opts, content) when is_binary(content) do
    append(opts, %{role: :developer, content: content})
  end

  @doc """
  Shorthand to append a system message.
  """
  @spec add_system(opts, binary) :: map()
  def add_system(opts, content) when is_binary(content) do
    append(opts, %{role: :system, content: content})
  end

  @doc """
  Execute `function_calls` using provided `functions` and append the outputs.

  The produced messages follow the OpenAI Responses format:
  `%{type: "function_call_output", call_id: id, output: result}`
  """
  @spec add_function_outputs(opts, [map()], map() | keyword()) :: map()
  def add_function_outputs(opts, function_calls, functions)
      when is_list(function_calls) and (is_map(functions) or is_list(functions)) do
    outputs = execute_function_calls(function_calls, functions)
    append(opts, outputs)
  end

  # -- Internals -----------------------------------------------------------------

  # Normalize opts to a map (atom keys preserved as-is). Always return a map.
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)

  # Normalize an existing input field into a list of message maps.
  defp normalize_input(nil), do: []
  defp normalize_input(input) when is_binary(input), do: [%{role: :user, content: input}]
  defp normalize_input(%{role: _r, content: _c} = msg), do: [msg]
  defp normalize_input(%{type: _t} = msg), do: [msg]

  defp normalize_input(list) when is_list(list), do: Enum.map(list, &to_message/1)

  defp normalize_input(other),
    do: raise(ArgumentError, "Invalid input value for :input: #{inspect(other)}")

  # Normalize provided messages (single or list) into message maps
  defp normalize_messages(messages) when is_binary(messages),
    do: [%{role: :user, content: messages}]

  defp normalize_messages(%{role: _r, content: _c} = msg), do: [msg]
  defp normalize_messages(%{"role" => _r, "content" => _c} = msg), do: [msg]
  defp normalize_messages(%{type: _t} = msg), do: [msg]
  defp normalize_messages(%{"type" => _t} = msg), do: [msg]
  defp normalize_messages(list) when is_list(list), do: Enum.map(list, &to_message/1)

  defp normalize_messages(other),
    do: raise(ArgumentError, "Invalid messages value: #{inspect(other)}")

  defp to_message(s) when is_binary(s), do: %{role: :user, content: s}
  defp to_message(%{role: _r, content: _c} = msg), do: msg
  # Allow tool/function output or other typed input items to pass through
  defp to_message(%{type: _t} = msg), do: msg

  defp to_message(%{"role" => _r, "content" => _c} = msg) do
    # Keep string-keyed maps as-is; Options.normalize will stringify later anyway
    msg
  end

  defp to_message(%{"type" => _t} = msg), do: msg

  defp to_message(other),
    do: raise(ArgumentError, "Expected binary or %{role, content} map, got: #{inspect(other)}")

  # Execute function calls and return function_call_output messages
  defp execute_function_calls(function_calls, functions) do
    Enum.map(function_calls, fn call ->
      call = Options.stringify_keys_shallow(call)
      function_name = call["name"]
      function = get_function(functions, function_name)

      result =
        case function do
          nil ->
            "Error: Function '#{function_name}' not found"

          f when is_function(f, 1) ->
            try do
              f.(call["arguments"])
            rescue
              e -> "Error calling function '#{function_name}': #{Exception.message(e)}"
            end

          _ ->
            "Error: Invalid function for '#{function_name}'"
        end

      %{
        type: "function_call_output",
        call_id: call["call_id"],
        output: result
      }
    end)
  end

  # Allow functions to be provided as a map or keyword list
  defp get_function(functions, name) when is_map(functions) do
    Map.get(functions, name) || Map.get(functions, to_string(name))
  end

  defp get_function(functions, name) when is_list(functions) do
    name_atom =
      cond do
        is_atom(name) ->
          name

        is_binary(name) ->
          try do
            String.to_existing_atom(name)
          rescue
            ArgumentError -> nil
          end

        true ->
          nil
      end

    Keyword.get(functions, name_atom)
  end
end
