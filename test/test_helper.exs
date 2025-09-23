Code.require_file("support/live_api_case.ex", __DIR__)

alias Responses.TestSupport.LiveApiCase

ExUnit.start(
  exclude: [:api],
  include: LiveApiCase.include_filters()
)
