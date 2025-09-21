defmodule OpenAI.Responses.PromptTest do
  use ExUnit.Case, async: true

  alias OpenAI.Responses.Prompt

  describe "add_* shorthands on empty opts" do
    test "add_user/2 wraps single message in a list" do
      assert %{input: [%{role: :user, content: "hello"}]} = Prompt.add_user(%{}, "hello")
    end

    test "add_developer/2 wraps single message in a list" do
      assert %{input: [%{role: :developer, content: "dev"}]} = Prompt.add_developer(%{}, "dev")
    end

    test "add_system/2 wraps single message in a list" do
      assert %{input: [%{role: :system, content: "sys"}]} = Prompt.add_system(%{}, "sys")
    end
  end

  describe "append/prepend normalization" do
    test "append/2 appends to list input" do
      opts = Prompt.add_user(%{}, "hi")
      assert %{input: [%{role: :user, content: "hi"}]} = opts

      opts = Prompt.append(opts, "second")
      assert %{input: [%{role: :user, content: "hi"}, %{role: :user, content: "second"}]} = opts
    end

    test "prepend/2 converts to list and preserves order" do
      opts = Prompt.add_user(%{}, "tail")
      opts = Prompt.prepend(opts, %{role: :system, content: "head"})

      assert %{input: [%{role: :system, content: "head"}, %{role: :user, content: "tail"}]} = opts
    end

    test "append/2 accepts list of messages and strings" do
      opts = %{}

      opts =
        Prompt.append(opts, [
          %{role: :developer, content: "style"},
          "user text"
        ])

      assert %{
               input: [
                 %{role: :developer, content: "style"},
                 %{role: :user, content: "user text"}
               ]
             } = opts
    end

    test "append/2 accepts string-keyed role/content maps (wrapped in list)" do
      opts = %{}
      opts = Prompt.append(opts, %{"role" => "system", "content" => "sys"})
      assert %{input: [%{"role" => "system", "content" => "sys"}]} = opts
    end

    test "append/2 and prepend/2 starting from empty list input" do
      opts = %{input: []}
      opts = Prompt.append(opts, %{role: :developer, content: "style"})
      assert %{input: [%{role: :developer, content: "style"}]} = opts

      opts = Prompt.prepend(opts, "first")

      assert %{input: [%{role: :user, content: "first"}, %{role: :developer, content: "style"}]} =
               opts
    end

    test "append/2 and prepend/2 accept mixed atom/string-keyed messages" do
      opts = %{}

      opts =
        Prompt.append(opts, [
          %{role: :system, content: "coach"},
          %{"role" => "developer", "content" => "pirate"}
        ])

      # single-message case becomes list because we passed two messages
      assert %{
               input: [
                 %{role: :system, content: "coach"},
                 %{"role" => "developer", "content" => "pirate"}
               ]
             } = opts

      # Prepend a string and ensure it's first
      opts = Prompt.prepend(opts, "hello")

      assert %{
               input: [
                 %{role: :user, content: "hello"},
                 %{role: :system, content: "coach"},
                 %{"role" => "developer", "content" => "pirate"}
               ]
             } = opts
    end
  end

  describe "normalizes existing non-list input" do
    test "append converts existing string input to list" do
      opts = %{input: "first"}
      opts = Prompt.append(opts, "second")

      assert %{input: [%{role: :user, content: "first"}, %{role: :user, content: "second"}]} =
               opts
    end

    test "prepend converts existing string input to list and preserves order" do
      opts = %{input: "tail"}
      opts = Prompt.prepend(opts, "head")

      assert %{input: [%{role: :user, content: "head"}, %{role: :user, content: "tail"}]} = opts
    end

    test "append converts existing single map input to list" do
      opts = %{input: %{role: :system, content: "only"}}
      opts = Prompt.append(opts, "next")

      assert %{input: [%{role: :system, content: "only"}, %{role: :user, content: "next"}]} = opts
    end
  end

  describe "function outputs composition" do
    test "add_function_outputs/3 appends to existing input" do
      opts = Prompt.add_user(%{}, "hi")

      function_calls = [
        %{name: "echo", call_id: "c1", arguments: %{"text" => "ok"}}
      ]

      functions = %{
        "echo" => fn %{"text" => t} -> t end
      }

      opts = Prompt.add_function_outputs(opts, function_calls, functions)

      assert %{
               input: [
                 %{role: :user, content: "hi"},
                 %{type: "function_call_output", call_id: "c1", output: "ok"}
               ]
             } = opts
    end
  end
end
