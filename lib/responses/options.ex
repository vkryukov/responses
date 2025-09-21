defmodule Responses.Options do
  @moduledoc false

  @typedoc "Normalized options map with string keys"
  @type t :: %{optional(String.t()) => any}

  @doc """
  Normalize user-provided options into a map with string keys.

  - Accepts keyword lists, maps with atom or string keys, or lists of {key, value} tuples.
  - Recursively stringifies keys for maps and keyword lists.
  - Preserves regular lists (arrays) as lists without converting to maps.
  - Raises `ArgumentError` on invalid list entries that look like malformed options.
  """
  @spec normalize(map | keyword) :: t
  def normalize(options) when is_map(options) do
    Map.new(options, fn {k, v} -> {to_string(k), normalize_value(v)} end)
  end

  def normalize(options) when is_list(options) do
    options
    |> Enum.map(fn
      {k, v} -> {to_string(k), normalize_value(v)}
      other -> raise ArgumentError, "Invalid option format: #{inspect(other)}"
    end)
    |> Map.new()
  end

  def normalize(other) do
    raise ArgumentError, "Options must be a map or keyword list, got: #{inspect(other)}"
  end

  # Internal recursive normalization
  defp normalize_value(value) when is_map(value) do
    normalize(value)
  end

  defp normalize_value(value) when is_list(value) do
    # If it's a keyword-like list (at least one tuple), try to normalize as options
    if value != [] and is_tuple(hd(value)) do
      try do
        normalize(value)
      rescue
        ArgumentError -> Enum.map(value, &normalize_value/1)
      end
    else
      # Regular list (array)
      Enum.map(value, &normalize_value/1)
    end
  end

  defp normalize_value(value), do: value

  @doc """
  Stringify top-level keys of a map. Does not descend into nested maps.
  """
  @spec stringify_keys_shallow(map) :: t
  def stringify_keys_shallow(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Stringify keys of a map deeply.
  """
  @spec stringify_keys_deep(map) :: t
  def stringify_keys_deep(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} ->
      v =
        cond do
          is_map(v) -> stringify_keys_deep(v)
          is_list(v) -> Enum.map(v, &stringify_if_map/1)
          true -> v
        end

      {to_string(k), v}
    end)
    |> Map.new()
  end

  defp stringify_if_map(v) when is_map(v), do: stringify_keys_deep(v)
  defp stringify_if_map(v), do: v

  @doc """
  Merge additions into a named section (e.g., "text") of options without dropping existing fields.

  - Section name can be atom or string; stored as string key.
  - Additions are deep-stringified to ensure consistent string keys.
  - Shallow merge at the section level (per-key) with additions taking precedence.
  """
  @spec merge_option(t, atom | String.t(), map) :: t
  def merge_option(options, section, additions) when is_map(options) and is_map(additions) do
    section = to_string(section)
    additions = stringify_keys_deep(additions)

    existing = Map.get(options, section)

    merged =
      case existing do
        %{} = map -> Map.merge(map, additions, fn _k, _old, new -> new end)
        _ -> additions
      end

    Map.put(options, section, merged)
  end

  @doc """
  Convenience wrapper to merge into the "text" section.
  """
  @spec merge_text(t, map) :: t
  def merge_text(options, additions) when is_map(options) and is_map(additions) do
    merge_option(options, "text", additions)
  end

  @doc """
  Preserve keys from a source map into options if they are not already present.

  Keys must be strings. If a key is absent in `options` and present in `source`, it is copied.
  """
  @spec preserve_from(t, map, [String.t()]) :: t
  def preserve_from(options, source, keys) when is_map(options) and is_map(source) do
    Enum.reduce(keys, options, fn key, acc ->
      with false <- Map.has_key?(acc, key),
           {:ok, value} <- Map.fetch(source, key) do
        Map.put(acc, key, value)
      else
        _ -> acc
      end
    end)
  end

  @doc """
  Preserve nested paths from a source map into options if they are not already present.

  - `paths` is a list of key-paths, where each path is a list of string keys.
  - If a value is absent at the path in `options` but present in `source`, it is copied.
  - Intermediate maps will be created in `options` as needed.
  - This does not copy any sibling keys; only the exact paths are preserved.
  """
  @spec preserve_paths(t, map, [[String.t()]]) :: t
  def preserve_paths(options, source, paths) when is_map(options) and is_map(source) do
    Enum.reduce(paths, options, fn path, acc ->
      case {get_in(acc, path), get_in(source, path)} do
        {nil, value} when not is_nil(value) -> put_in_new(acc, path, value)
        _ -> acc
      end
    end)
  end

  # Create intermediate maps as needed and put the value at the given path
  defp put_in_new(map, [k], value) when is_binary(k), do: Map.put(map, k, value)

  defp put_in_new(map, [k | rest], value) when is_binary(k) and is_list(rest) do
    child =
      case Map.get(map, k) do
        %{} = m -> m
        _ -> %{}
      end

    Map.put(map, k, put_in_new(child, rest, value))
  end
end
