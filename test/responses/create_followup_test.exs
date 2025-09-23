defmodule Responses.CreateFollowupTest do
  use ExUnit.Case, async: true

  describe "xAI follow-up option filtering" do
    test "chained xAI requests should drop reasoning effort" do
      # Create a mock previous response that includes reasoning effort in the response body
      # This simulates what would happen if xAI returns reasoning effort in their response
      mock_response_body = %{
        "id" => "resp_test_123",
        "model" => "grok-4-fast",
        "reasoning" => %{"effort" => "medium"},
        "text" => %{"verbosity" => "medium"}
      }

      # Simulate the create/2 flow up to the point just before the outbound HTTP request
      provider = Responses.Provider.get!(:xai)
      normalized = Responses.Options.normalize(input: "Follow-up question")
      preserved_paths = [["model"], ["reasoning", "effort"], ["text", "verbosity"]]
      unsupported_paths = Enum.map(provider.unsupported_options, fn {path, _message} -> path end)

      options_with_id = Map.put(normalized, "previous_response_id", mock_response_body["id"])

      preserved_options =
        Responses.Options.preserve_paths(options_with_id, mock_response_body, preserved_paths)

      stripped_options =
        Responses.Options.drop_preserved_paths(
          preserved_options,
          mock_response_body,
          normalized,
          unsupported_paths
        )

      # Desired behavior: xAI follow-ups must not include the unsupported reasoning effort option
      assert stripped_options["model"] == "grok-4-fast"
      assert is_nil(get_in(stripped_options, ["reasoning", "effort"]))
      assert stripped_options["previous_response_id"] == "resp_test_123"
    end
  end
end
