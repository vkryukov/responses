defmodule Responses.RequestTelemetryTest do
  use ExUnit.Case

  setup do
    original_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", original_key || "test-key")

    on_exit(fn ->
      if original_key do
        System.put_env("OPENAI_API_KEY", original_key)
      else
        System.delete_env("OPENAI_API_KEY")
      end
    end)

    :ok
  end

  test "request emits telemetry event with provider metadata" do
    ref = make_ref()

    :telemetry.attach_many(
      {__MODULE__, ref},
      [[:responses, :request, :stop]],
      &__MODULE__.telemetry_handler/4,
      self()
    )

    provider = %{Responses.Provider.get!(:openai) | base_url: "http://127.0.0.1:65535"}

    try do
      Responses.request(provider: provider, url: "/telemetry", method: :get, retry: false)
    after
      :telemetry.detach({__MODULE__, ref})
    end

    assert_receive {:telemetry_received, measurements, metadata}
    assert is_integer(measurements.duration)
    assert metadata.provider == :openai
    assert String.downcase(to_string(metadata.method || :get)) == "get"
  end

  def telemetry_handler(_event, measurements, metadata, parent) do
    send(parent, {:telemetry_received, measurements, metadata})
  end
end
