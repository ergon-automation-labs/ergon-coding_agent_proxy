defmodule BotArmyCodingAgentProxy.NATS.ConsumerTest do
  use ExUnit.Case, async: true
  @moduletag :nats

  alias BotArmyCodingAgentProxy.NATS.Consumer

  test "subject_for_lane maps known lanes" do
    assert Consumer.subject_for_lane("interactive") == "pi-go.llm.request.chat.interactive"
    assert Consumer.subject_for_lane("urgent") == "pi-go.llm.request.chat.urgent"
    assert Consumer.subject_for_lane("background") == "pi-go.llm.request.chat.background"
  end

  test "subject_for_lane falls back to interactive" do
    assert Consumer.subject_for_lane("unknown") == "pi-go.llm.request.chat.interactive"
  end

  test "build_forward_payload uses defaults and keeps request data" do
    payload =
      Consumer.build_forward_payload(%{
        "prompt_context" => %{"prompt" => "hello"},
        "tenant_id" => "tenant",
        "timeout_ms" => 12_000
      })

    assert payload["request_type"] == "chat"
    assert payload["model_preference"] == "auto"
    assert payload["timeout_ms"] == 12_000
    assert payload["tenant_id"] == "tenant"
    assert payload["prompt_context"] == %{"prompt" => "hello"}
    assert is_binary(payload["request_id"])
  end
end
