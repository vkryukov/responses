defmodule ResponsesTest do
  use ExUnit.Case

  alias Responses
  alias Responses.TestSupport.LiveApiCase

  @tag :api
  test "create with explicit input and model returns correct text" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :default)

      response =
        Responses.create!(
          input: "Respond with exactly 5 words including the word 'elixir'",
          model: model
        )

      response_text = response.text

      assert response_text =~ ~r/elixir/i
      # Check that response is reasonably short (3-7 words) instead of exactly 5
      word_count = String.split(response_text, " ") |> Enum.count()
      assert word_count >= 3 and word_count <= 7
      assert LiveApiCase.model_used?(response.body["model"], provider, :default)
    end)
  end

  @tag :api
  test "create with an input and model arguments uses the correct model" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :alternate)

      response =
        Responses.create!(
          input: "Write a haiku about Elixir programming language",
          model: model
        )

      assert String.split(response.text, "\n") |> Enum.count() == 3
      assert LiveApiCase.model_used?(response.body["model"], provider, :alternate)
      # Ensure it's not using the default model
      refute LiveApiCase.model_used?(response.body["model"], provider, :default)
    end)
  end

  @tag :api
  test "create with a map argument" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :alternate)

      response =
        Responses.create!(%{
          input: "Reply with exactly three words about Elixir",
          model: model
        })

      assert String.split(response.text, " ") |> Enum.count() == 3
      assert LiveApiCase.model_used?(response.body["model"], provider, :alternate)
    end)
  end

  @tag :api
  test "create with a map including stream callback" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :default)

      collected_text = Agent.start_link(fn -> "" end) |> elem(1)

      {:ok, response} =
        Responses.create(%{
          input: "Count from 1 to 3",
          model: model,
          stream: fn
            {:ok, %{event: "response.output_text.delta", data: %{"delta" => text}}} ->
              Agent.update(collected_text, &(&1 <> text))
              :ok

            _ ->
              :ok
          end
        })

      final_text = Agent.get(collected_text, & &1)
      Agent.stop(collected_text)

      assert response.text != nil
      assert final_text =~ ~r/1.*2.*3/s
    end)
  end

  @tag :api
  test "create with a map with atom and string keys" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :alternate)

      # Maps with mixed atom and string keys should work
      response =
        Responses.create!(%{
          "input" => "Reply with exactly two words",
          :model => model
        })

      assert String.split(response.text, " ") |> Enum.count() == 2
      assert LiveApiCase.model_used?(response.body["model"], provider, :alternate)
    end)
  end

  @tag :api
  test "list_models returns available models" do
    LiveApiCase.run_for_each_provider(fn provider ->
      models = Responses.list_models(provider)

      assert is_list(models)
      assert length(models) > 0
      assert Enum.all?(models, &Map.has_key?(&1, "id"))
    end)
  end

  @tag :api
  test "list_models with match filter returns filtered models" do
    LiveApiCase.run_for_each_provider(fn provider ->
      match = LiveApiCase.list_match(provider)
      models = Responses.list_models(provider, match)

      assert is_list(models)
      assert Enum.all?(models, &String.contains?(&1["id"], match))
    end)
  end

  @tag :api
  test "create with invalid parameter returns error" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :default)

      result =
        Responses.create(nonsensical_param: "invalid value", input: "test", model: model)

      assert {:error, error} = result
      assert is_map(error)
    end)
  end

  @tag :api
  test "create with invalid model returns error" do
    LiveApiCase.run_for_each_provider(fn provider ->
      result = Responses.create(input: "test", model: LiveApiCase.invalid_model(provider))

      assert {:error, error} = result
      assert is_map(error)
    end)
  end

  @tag :api
  test "response can be piped to create a follow up response" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :default)

      response =
        Responses.create!(
          input: "Write a haiku about Elixir programming language",
          model: model
        )

      follow_up_response = response |> Responses.create!(input: "What is this haiku about?")

      assert follow_up_response.text =~ ~r/Elixir/
    end)
  end

  @tag :api
  test "create/2 preserves model from previous response when not explicitly provided" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :alternate)

      # Create initial response with a specific model
      initial_response =
        Responses.create!(
          input: "Say hello",
          model: model
        )

      # Verify the initial response uses the specified model
      assert LiveApiCase.model_used?(initial_response.body["model"], provider, :alternate)

      # Create follow-up without specifying model
      sanitized_response = LiveApiCase.prepare_follow_up(initial_response, provider)

      follow_up_response = Responses.create!(sanitized_response, input: "Say goodbye")

      # The follow-up should use the same model as the initial response
      assert follow_up_response.body["model"] == initial_response.body["model"]
    end)
  end

  @tag :api
  test "create/2 accepts maps for options" do
    LiveApiCase.run_for_each_provider(fn provider ->
      model = LiveApiCase.model(provider, :default)

      # Create initial response
      initial_response = Responses.create!(input: "Say hello", model: model)

      # Create follow-up with map options
      sanitized_response = LiveApiCase.prepare_follow_up(initial_response, provider)

      follow_up_response =
        Responses.create!(sanitized_response, %{
          input: "Say goodbye in exactly two words",
          temperature: 0.5
        })

      assert String.split(follow_up_response.text, " ") |> Enum.count() == 2
      assert follow_up_response.body["previous_response_id"] == initial_response.body["id"]
    end)
  end

  @tag :api
  test "create/2 allows overriding model from previous response" do
    LiveApiCase.run_for_each_provider(fn provider ->
      # Create initial response with a specific model
      initial_response =
        Responses.create!(
          input: "Say hello",
          model: LiveApiCase.model(provider, :alternate)
        )

      # Create follow-up with a different model
      sanitized_response = LiveApiCase.prepare_follow_up(initial_response, provider)

      follow_up_response =
        Responses.create!(
          sanitized_response,
          input: "Say goodbye",
          model: LiveApiCase.model(provider, :small)
        )

      # The follow-up should use the explicitly provided model
      assert LiveApiCase.model_used?(follow_up_response.body["model"], provider, :small)
      # And not the model from the previous response
      refute LiveApiCase.model_used?(follow_up_response.body["model"], provider, :alternate)
    end)
  end

  @tag :api
  test "create/2 preserves reasoning effort from previous response when not explicitly provided" do
    LiveApiCase.run_for_each_provider(
      fn provider ->
        # Create initial response with high reasoning effort using provider-specific reasoning model
        initial_response =
          Responses.create!(
            input: "What is 2+2?",
            model: LiveApiCase.model(provider, :reasoning),
            reasoning: %{effort: "high"}
          )

        # Verify the initial response has reasoning settings
        assert initial_response.body["reasoning"]["effort"] == "high"

        # Create follow-up without specifying reasoning
        sanitized_response = LiveApiCase.prepare_follow_up(initial_response, provider)

        follow_up_response = Responses.create!(sanitized_response, input: "What about 3+3?")

        # The follow-up should preserve the reasoning effort
        assert follow_up_response.body["reasoning"]["effort"] == "high"
      end,
      require: [:reasoning]
    )
  end

  @tag :api
  test "create/2 allows overriding reasoning effort from previous response" do
    LiveApiCase.run_for_each_provider(
      fn provider ->
        # Create initial response with high reasoning effort using provider-specific reasoning model
        initial_response =
          Responses.create!(
            input: "What is 2+2?",
            model: LiveApiCase.model(provider, :reasoning),
            reasoning: %{effort: "high"}
          )

        # Create follow-up with different reasoning effort
        follow_up_response =
          Responses.create!(
            initial_response,
            input: "What about 3+3?",
            reasoning: %{effort: "low"}
          )

        # The follow-up should use the explicitly provided reasoning effort
        assert follow_up_response.body["reasoning"]["effort"] == "low"
      end,
      require: [:reasoning]
    )
  end

  @tag :api
  test "create/2 preserves text verbosity from previous response when not explicitly provided" do
    LiveApiCase.run_for_each_provider(
      fn provider ->
        # Create initial response with specific verbosity
        initial_response =
          Responses.create!(
            input: "Explain addition",
            model: LiveApiCase.model(provider, :reasoning),
            text: %{verbosity: "low"}
          )

        # Verify the initial response has text settings
        assert initial_response.body["text"]["verbosity"] == "low"

        # Create follow-up without specifying text settings
        sanitized_response = LiveApiCase.prepare_follow_up(initial_response, provider)

        follow_up_response =
          Responses.create!(sanitized_response, input: "What about subtraction?")

        # The follow-up should preserve the text verbosity
        assert follow_up_response.body["text"]["verbosity"] == "low"
      end,
      require: [:reasoning]
    )
  end

  @tag :api
  test "create/2 allows overriding text verbosity from previous response" do
    LiveApiCase.run_for_each_provider(
      fn provider ->
        # Create initial response with low verbosity
        initial_response =
          Responses.create!(
            input: "Explain addition",
            model: LiveApiCase.model(provider, :reasoning),
            text: %{verbosity: "low"}
          )

        # Create follow-up with different verbosity
        follow_up_response =
          Responses.create!(
            initial_response,
            input: "What about multiplication?",
            text: %{verbosity: "high"}
          )

        # The follow-up should use the explicitly provided verbosity
        assert follow_up_response.body["text"]["verbosity"] == "high"
      end,
      require: [:reasoning]
    )
  end

  @tag :api
  test "create/2 preserves multiple LLM options together" do
    LiveApiCase.run_for_each_provider(
      fn provider ->
        # Create initial response with multiple LLM options
        initial_response =
          Responses.create!(
            input: "Solve this problem",
            model: LiveApiCase.model(provider, :reasoning),
            reasoning: %{effort: "high"},
            text: %{verbosity: "low"}
          )

        # Create follow-up without specifying any LLM options
        sanitized_response = LiveApiCase.prepare_follow_up(initial_response, provider)

        follow_up_response =
          Responses.create!(sanitized_response, input: "What about a harder problem?")

        # All LLM options should be preserved
        assert follow_up_response.body["model"] == initial_response.body["model"]
        assert follow_up_response.body["reasoning"]["effort"] == "high"
        assert follow_up_response.body["text"]["verbosity"] == "low"
      end,
      require: [:reasoning]
    )
  end

  @tag :api
  test "create/2 allows partial override of LLM options" do
    LiveApiCase.run_for_each_provider(
      fn provider ->
        # Create initial response with multiple LLM options
        initial_response =
          Responses.create!(
            input: "Solve this problem",
            model: LiveApiCase.model(provider, :reasoning),
            reasoning: %{effort: "high"},
            text: %{verbosity: "low"}
          )

        # Create follow-up overriding only reasoning
        follow_up_response =
          Responses.create!(
            initial_response,
            input: "Another problem",
            reasoning: %{effort: "medium"}
          )

        # Reasoning should be overridden, but model and text should be preserved
        assert follow_up_response.body["model"] == initial_response.body["model"]
        assert follow_up_response.body["reasoning"]["effort"] == "medium"
        assert follow_up_response.body["text"]["verbosity"] == "low"
      end,
      require: [:reasoning]
    )
  end

  @tag :api
  test "create/1 with manual previous_response_id and explicit model uses the specified model" do
    LiveApiCase.run_for_each_provider(fn provider ->
      # Create initial response with a specific model
      initial_response =
        Responses.create!(
          input: "Say hello",
          model: LiveApiCase.model(provider, :small)
        )

      # Create follow-up using manual previous_response_id with explicit model
      follow_up_response =
        Responses.create!(
          input: "Say goodbye",
          previous_response_id: initial_response.body["id"],
          model: LiveApiCase.model(provider, :alternate)
        )

      # The follow-up should use the explicitly provided model
      assert LiveApiCase.model_used?(follow_up_response.body["model"], provider, :alternate)
      # And not the model from the previous response
      refute LiveApiCase.model_used?(follow_up_response.body["model"], provider, :small)
    end)
  end

  describe "create with schema option" do
    @tag :api
    test "create with schema option generates structured response with map schema" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        response =
          Responses.create!(
            input: "Generate user data for John Doe with email john@example.com",
            schema: %{
              name: :string,
              email: {:string, format: "email"},
              age: :number
            },
            model: model
          )

        assert response.parsed != nil
        assert response.parse_error == nil
        assert is_map(response.parsed)
        assert Map.has_key?(response.parsed, "name")
        assert Map.has_key?(response.parsed, "email")
        assert response.parsed["email"] =~ "@"
      end)
    end

    @tag :api
    test "create with schema option generates structured response with keyword list schema" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        response =
          Responses.create!(
            input: "Generate user data for Jane Smith with username @jane123",
            schema: [
              username: {:string, pattern: "^@[a-zA-Z0-9_]+$"},
              name: :string,
              active: :boolean
            ],
            model: model
          )

        assert response.parsed != nil
        assert response.parse_error == nil
        assert is_map(response.parsed)
        assert Map.has_key?(response.parsed, "username")
        assert Map.has_key?(response.parsed, "name")
        assert Map.has_key?(response.parsed, "active")
        assert response.parsed["username"] =~ ~r/^@/
        assert is_boolean(response.parsed["active"])
      end)
    end

    @tag :api
    test "create with complex nested schema" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        response =
          Responses.create!(
            input: "Generate a user profile with contact information",
            schema: %{
              user: %{
                name: :string,
                contact: %{
                  email: {:string, format: "email"},
                  phone: :string
                }
              },
              metadata: %{
                created_at: :string,
                version: :number
              }
            },
            model: model
          )

        assert response.parsed != nil
        assert response.parse_error == nil
        assert Map.has_key?(response.parsed, "user")
        assert Map.has_key?(response.parsed, "metadata")
        assert Map.has_key?(response.parsed["user"], "contact")
        assert Map.has_key?(response.parsed["user"]["contact"], "email")
      end)
    end

    @tag :api
    test "create with array schema" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        response =
          Responses.create!(
            input: "Generate a list of 3 users",
            schema: %{
              users:
                {:array,
                 %{
                   name: :string,
                   age: :number
                 }},
              total_count: :number
            },
            model: model
          )

        assert response.parsed != nil
        assert response.parse_error == nil
        assert Map.has_key?(response.parsed, "users")
        assert is_list(response.parsed["users"])
        assert length(response.parsed["users"]) >= 1

        first_user = List.first(response.parsed["users"])
        assert Map.has_key?(first_user, "name")
        assert Map.has_key?(first_user, "age")
      end)
    end

    @tag :api
    test "response without schema has no parsed field set" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        response = Responses.create!(input: "Just return some text", model: model)

        # For non-structured responses, parsed should not be set
        # extract_json detects it's not a structured response and sets parse_error
        assert response.parsed == nil
        assert response.parse_error == nil
        assert response.text != nil
      end)
    end
  end

  describe "run/2 with function calling" do
    @tag :api
    test "run/2 executes functions and returns all responses" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        # Define mock functions
        functions = %{
          "get_current_time" => fn %{} ->
            "2024-01-15 10:30:00 UTC"
          end,
          "add_numbers" => fn %{"a" => a, "b" => b} ->
            "The sum of #{a} and #{b} is #{a + b}"
          end
        }

        # Define function tools
        time_tool =
          Responses.Schema.build_function(
            "get_current_time",
            "Get the current time",
            %{}
          )

        add_tool =
          Responses.Schema.build_function(
            "add_numbers",
            "Add two numbers together",
            %{a: :number, b: :number}
          )

        # Run the conversation
        responses =
          Responses.run(
            [
              input: "What time is it and what is 15 + 27?",
              tools: [time_tool, add_tool],
              model: model
            ],
            functions
          )

        # Should have at least 2 responses (initial + final)
        assert length(responses) >= 2

        # First response should have function calls
        first_response = List.first(responses)
        assert first_response.function_calls != nil
        assert length(first_response.function_calls) > 0

        # Last response should have no function calls
        last_response = List.last(responses)
        assert last_response.function_calls == nil || last_response.function_calls == []

        # Final text should contain the results
        assert last_response.text =~ "42"
        assert last_response.text =~ "10:30"
      end)
    end

    @tag :api
    test "run/2 handles missing functions gracefully" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        # Define only one function
        functions = %{
          "get_weather" => fn %{"location" => location} ->
            "The weather in #{location} is sunny"
          end
        }

        # Define tools including one that doesn't have an implementation
        weather_tool =
          Responses.Schema.build_function(
            "get_weather",
            "Get weather for a location",
            %{location: :string}
          )

        time_tool =
          Responses.Schema.build_function(
            "get_time",
            "Get current time",
            %{}
          )

        responses =
          Responses.run(
            [
              input: "What's the weather in Paris and what time is it?",
              tools: [weather_tool, time_tool],
              model: model
            ],
            functions
          )

        # Should complete successfully
        assert is_list(responses)
        assert length(responses) >= 2

        # Final response should mention the error or handle it gracefully
        last_response = List.last(responses)
        assert last_response.text != nil
      end)
    end

    @tag :api
    test "run/2 works with keyword list of functions" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        functions = [
          get_weather: fn %{"location" => location} ->
            "Weather in #{location}: 20°C"
          end
        ]

        weather_tool =
          Responses.Schema.build_function(
            "get_weather",
            "Get weather",
            %{location: :string}
          )

        responses =
          Responses.run(
            [
              input: "What's the weather in London?",
              tools: [weather_tool],
              model: model
            ],
            functions
          )

        assert is_list(responses)
        last_response = List.last(responses)
        assert last_response.text =~ "20°C"
      end)
    end

    @tag :api
    test "run!/2 raises on error" do
      LiveApiCase.run_for_each_provider(fn provider ->
        invalid_model = LiveApiCase.invalid_model(provider)

        # Test with invalid input that would cause an error
        assert_raise RuntimeError, fn ->
          Responses.run!(
            [input: "test", model: invalid_model],
            %{}
          )
        end
      end)
    end

    @tag :api
    test "run/2 handles function exceptions" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        functions = %{
          "divide" => fn %{"a" => a, "b" => b} ->
            if b == 0 do
              raise "Division by zero"
            else
              "#{a} / #{b} = #{a / b}"
            end
          end
        }

        divide_tool =
          Responses.Schema.build_function(
            "divide",
            "Divide two numbers",
            %{a: :number, b: :number}
          )

        responses =
          Responses.run(
            [
              input: "What is 10 divided by 5?",
              tools: [divide_tool],
              model: model
            ],
            functions
          )

        # Should handle normal division
        assert is_list(responses)
        assert length(responses) >= 2

        # Test division by zero separately
        zero_responses =
          Responses.run(
            [
              input: "What is 10 divided by 0?",
              tools: [divide_tool],
              model: model
            ],
            functions
          )

        # Should handle the exception gracefully
        assert is_list(zero_responses)
      end)
    end

    @tag :api
    test "run/2 with no function calls returns single response" do
      LiveApiCase.run_for_each_provider(fn provider ->
        model = LiveApiCase.model(provider, :default)

        functions = %{
          "unused_function" => fn _ -> "This won't be called" end
        }

        responses =
          Responses.run(
            [input: "Just tell me a joke about programming", model: model],
            functions
          )

        # Should only have one response since no functions were called
        assert length(responses) == 1
        assert List.first(responses).text != nil
      end)
    end
  end
end
