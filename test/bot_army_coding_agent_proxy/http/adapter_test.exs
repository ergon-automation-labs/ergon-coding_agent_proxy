defmodule BotArmyCodingAgentProxy.HTTP.AdapterTest do
  use ExUnit.Case, async: true
  @moduletag :http

  alias BotArmyCodingAgentProxy.HTTP.Adapter

  test "build_proxy_payload formats prompt from system and messages" do
    payload =
      Adapter.build_proxy_payload(%{
        "system" => "be brief",
        "messages" => [
          %{"role" => "user", "content" => "hello"},
          %{"role" => "assistant", "content" => [%{"type" => "text", "text" => "hi"}]}
        ],
        "metadata" => %{"lane" => "urgent"}
      })

    assert payload["lane"] == "urgent"
    assert payload["prompt_context"]["prompt"] =~ "System: be brief"
    assert payload["prompt_context"]["prompt"] =~ "[user] hello"
    assert payload["prompt_context"]["prompt"] =~ "[assistant] hi"
  end

  test "build_anthropic_response wraps downstream content" do
    response =
      Adapter.build_anthropic_response(
        %{
          "response" => %{"content" => "done"}
        },
        "claude-test"
      )

    assert response["type"] == "message"
    assert response["role"] == "assistant"
    assert response["model"] == "claude-test"
    assert response["content"] == [%{"type" => "text", "text" => "done"}]
  end
end
