defmodule Responses.StreamTest do
  use ExUnit.Case

  alias Responses
  alias Responses.TestSupport.LiveApiCase

  # Helper to unwrap successful chunks for testing
  defp unwrap_chunks(chunks) do
    chunks
    |> Enum.filter(fn
      {:ok, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {:ok, chunk} -> chunk end)
  end

  describe "create/1 with stream: option" do
    @tag :api
    test "streams response chunks with callback function" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        {:ok, agent} = Agent.start_link(fn -> [] end)

        result =
          Responses.create(
            input: "Count from 1 to 3",
            model: model,
            stream: fn result ->
              Agent.update(agent, &[result | &1])
              :ok
            end
          )

        assert {:ok, _} = result
        raw_chunks = Agent.get(agent, & &1) |> Enum.reverse()
        chunks = unwrap_chunks(raw_chunks)

        # Should have multiple chunks
        assert length(chunks) > 0

        # Each chunk should have event and data keys
        assert Enum.all?(chunks, &(Map.has_key?(&1, :event) && Map.has_key?(&1, :data)))

        # Should have at least one text delta event
        text_deltas = Enum.filter(chunks, &(&1.event == "response.output_text.delta"))
        assert length(text_deltas) > 0

        # Should have a completed event
        assert Enum.any?(chunks, &(&1.event == "response.completed"))

        Agent.stop(agent)
      end)
    end

    @tag :api
    test "delta helper accumulates text properly" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        buffer = :ets.new(:buffer, [:set, :public])
        :ets.insert(buffer, {:text, ""})

        delta_fn =
          Responses.Stream.delta(fn text ->
            [{:text, current}] = :ets.lookup(buffer, :text)
            :ets.insert(buffer, {:text, current <> text})
          end)

        {:ok, _} =
          Responses.create(
            input: "Write exactly: The quick brown fox",
            stream: delta_fn,
            model: model
          )

        [{:text, accumulated}] = :ets.lookup(buffer, :text)
        assert accumulated =~ "quick brown fox"

        :ets.delete(buffer)
      end)
    end

    @tag :api
    test "stream with schema produces structured output" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        buffer = :ets.new(:buffer, [:set, :public])
        :ets.insert(buffer, {:text, ""})

        delta_fn =
          Responses.Stream.delta(fn text ->
            [{:text, current}] = :ets.lookup(buffer, :text)
            :ets.insert(buffer, {:text, current <> text})
          end)

        {:ok, _} =
          Responses.create(
            input: "Generate a user",
            schema: %{name: :string, age: :number},
            stream: delta_fn,
            model: model
          )

        [{:text, accumulated}] = :ets.lookup(buffer, :text)
        assert {:ok, parsed} = Jason.decode(accumulated)
        assert Map.has_key?(parsed, "name")
        assert Map.has_key?(parsed, "age")

        :ets.delete(buffer)
      end)
    end
  end

  describe "text_deltas/1 and json_events/1 helpers" do
    @tag :api
    test "text_deltas extracts text content from stream" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        text =
          Responses.stream(input: "Write exactly: Hello World", model: model)
          |> Responses.Stream.text_deltas()
          |> Enum.join()

        assert text =~ "Hello World"
      end)
    end

    @tag :api
    test "json_events works directly on response streams" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        events =
          Responses.stream(
            input: "Generate simple object with test=true",
            schema: %{test: :boolean},
            model: model
          )
          |> Responses.Stream.json_events()
          |> Enum.to_list()

        assert :start_object in events
        assert {:string, "test"} in events
        assert {:boolean, true} in events
        assert :end_object in events
      end)
    end

    @tag :api
    test "text_deltas can still be used for text-only processing" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        text =
          Responses.stream(
            input: "Write exactly: Hello World",
            schema: %{message: :string},
            model: model
          )
          |> Responses.Stream.text_deltas()
          |> Enum.join()

        assert text =~ "Hello World"
      end)
    end
  end

  describe "json_events/1 comprehensive tests" do
    @tag :api
    test "streams JSON parsing events for structured output" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        events =
          Responses.stream(
            input: "List first two U.S. presidents",
            schema: %{
              presidents:
                {:array,
                 %{
                   name: :string,
                   birth_year: :integer
                 }}
            },
            model: model
          )
          |> Responses.Stream.json_events()
          |> Enum.to_list()

        # Should start with object
        assert :start_object in events
        assert :end_object in events

        # Should have the presidents key
        assert {:string, "presidents"} in events

        # Should have array markers
        assert :start_array in events
        assert :end_array in events

        # Should have the field names
        assert {:string, "name"} in events
        assert {:string, "birth_year"} in events

        # Should have colons between keys and values
        assert :colon in events

        # Should have at least one comma (between array elements)
        assert :comma in events

        # Should have actual president data
        name_events =
          events
          |> Enum.filter(fn
            {:string, val} when val not in ["presidents", "name", "birth_year"] -> true
            _ -> false
          end)

        # At least 2 president names
        assert length(name_events) >= 2

        # Should have birth years as integers
        integer_events =
          events
          |> Enum.filter(fn
            {:integer, _} -> true
            _ -> false
          end)

        # At least 2 birth years
        assert length(integer_events) >= 2
      end)
    end

    @tag :api
    test "works with simple object schema" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        events =
          Responses.stream(
            input: "Generate a user with name 'Alice' and age 30",
            schema: %{name: :string, age: :integer},
            model: model
          )
          |> Responses.Stream.json_events()
          |> Enum.to_list()

        assert :start_object in events
        assert {:string, "name"} in events
        assert {:string, "Alice"} in events
        assert {:string, "age"} in events
        assert {:integer, 30} in events
        assert :end_object in events
      end)
    end

    @tag :api
    test "handles nested objects" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        events =
          Responses.stream(
            input: "Create product: laptop, $999, specs with 16GB RAM",
            schema: %{
              name: :string,
              price: :number,
              specs: %{
                ram: :string
              }
            },
            model: model
          )
          |> Responses.Stream.json_events()
          |> Enum.to_list()

        # Count object markers
        start_objects = events |> Enum.count(&(&1 == :start_object))
        end_objects = events |> Enum.count(&(&1 == :end_object))

        # Main object + specs object
        assert start_objects == 2
        assert end_objects == 2
        assert {:string, "specs"} in events
        assert {:string, "ram"} in events
      end)
    end

    @tag :api
    test "preserves event order for reconstruction" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        events =
          Responses.stream(
            input: "Simple object with one field 'test' = true",
            schema: %{test: :boolean},
            model: model
          )
          |> Responses.Stream.json_events()
          |> Enum.to_list()

        # The exact order should allow reconstruction
        expected_order = [
          :start_object,
          {:string, "test"},
          :colon,
          {:boolean, true},
          :end_object
        ]

        assert events == expected_order
      end)
    end

    @tag :api
    test "streams events incrementally without waiting for complete response" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        # Use an agent to track that events arrive before completion
        {:ok, agent} = Agent.start_link(fn -> [] end)
        completed_ref = make_ref()

        Responses.stream(
          input: "List 5 items",
          schema: %{items: {:array, :string}},
          model: model
        )
        |> Responses.Stream.json_events()
        |> Stream.each(fn event ->
          # Record event arrival
          Agent.update(agent, fn events ->
            timestamp = System.monotonic_time(:millisecond)
            [{event, timestamp} | events]
          end)

          # If we see end_object, send completion signal
          if event == :end_object do
            send(self(), {completed_ref, :done})
          end
        end)
        |> Stream.run()

        # Wait for completion
        receive do
          {^completed_ref, :done} -> :ok
        after
          10_000 -> flunk("Stream did not complete")
        end

        # Get all events with timestamps
        timestamped_events = Agent.get(agent, & &1) |> Enum.reverse()
        Agent.stop(agent)

        # Events should arrive over time, not all at once
        timestamps = timestamped_events |> Enum.map(fn {_, ts} -> ts end)
        time_span = List.last(timestamps) - List.first(timestamps)

        # Should have multiple events
        assert length(timestamped_events) > 5

        # Time span should be greater than 0, indicating incremental arrival
        assert time_span > 0
      end)
    end
  end

  describe "stream/1 enumerable interface" do
    @tag :api
    test "returns enumerable that yields wrapped results" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        results =
          for result <- Responses.stream(input: "Say hello", model: model) do
            result
          end

        assert length(results) > 0

        # Filter successful chunks
        chunks = unwrap_chunks(results)
        assert length(chunks) > 0
        assert Enum.all?(chunks, &(Map.has_key?(&1, :event) && Map.has_key?(&1, :data)))
      end)
    end

    @tag :api
    test "can filter and process text deltas" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        text =
          Responses.stream(input: "Write: Hello World", model: model)
          |> Responses.Stream.text_deltas()
          |> Enum.join()

        assert text =~ "Hello World"
      end)
    end

    @tag :api
    test "accumulates results with error handling" do
      LiveApiCase.run_with_default_model(fn _provider, model ->
        result =
          Responses.stream(input: "Write ABC", model: model)
          |> Enum.reduce(%{text: "", events: [], errors: []}, fn result, acc ->
            case result do
              {:ok, %{event: "response.output_text.delta", data: data}} ->
                %{acc | text: acc.text <> data["delta"]}

              {:ok, chunk} ->
                %{acc | events: [chunk.event | acc.events]}

              {:error, error} ->
                %{acc | errors: [error | acc.errors]}
            end
          end)

        condensed_text = result.text |> String.replace(~r/\s+/, "")
        assert condensed_text =~ "ABC"
        assert "response.completed" in result.events
      end)
    end
  end
end
