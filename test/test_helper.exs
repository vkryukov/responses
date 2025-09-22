Code.require_file("support/live_api_case.ex", __DIR__)

alias Responses.TestSupport.LiveApiCase

ExUnit.start(
  exclude: [:api, :openai_api, :xai_api],
  include: LiveApiCase.include_filters()
)
