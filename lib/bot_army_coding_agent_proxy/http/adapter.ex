defmodule BotArmyCodingAgentProxy.HTTP.Adapter do
  @moduledoc """
  Translates Anthropic-style HTTP payloads to coding-agent NATS proxy requests.
  """

  @default_model "claude-sonnet-4-20250514"

  def build_proxy_payload(body) when is_map(body) do
    messages = Map.get(body, "messages", [])
    system = Map.get(body, "system")
    lane = body |> Map.get("metadata", %{}) |> Map.get("lane", "interactive")

    prompt =
      [build_system_line(system), build_messages_block(messages)]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    %{
      "lane" => lane,
      "request_type" => "chat",
      "model_preference" => "auto",
      "timeout_ms" => Map.get(body, "timeout_ms", 60_000),
      "prompt_context" => %{
        "prompt" => prompt,
        "messages" => messages,
        "system" => system
      }
    }
  end

  def build_anthropic_response(proxy_response, requested_model) when is_map(proxy_response) do
    text =
      proxy_response
      |> extract_response_text()
      |> case do
        "" -> "No response content returned from coding agent proxy."
        value -> value
      end

    %{
      "id" => "msg_#{UUID.uuid4()}",
      "type" => "message",
      "role" => "assistant",
      "model" => requested_model || @default_model,
      "content" => [%{"type" => "text", "text" => text}],
      "stop_reason" => "end_turn",
      "stop_sequence" => nil,
      "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
    }
  end

  defp build_system_line(nil), do: ""
  defp build_system_line(""), do: ""
  defp build_system_line(system) when is_binary(system), do: "System: #{String.trim(system)}"

  defp build_system_line(system) when is_list(system) do
    text =
      system
      |> Enum.map_join("\n", &extract_text_content/1)
      |> String.trim()

    if text == "", do: "", else: "System: #{text}"
  end

  defp build_system_line(_), do: ""

  defp build_messages_block(messages) when is_list(messages) do
    messages
    |> Enum.map_join("\n", fn msg ->
      role = msg |> Map.get("role", "user") |> to_string() |> String.trim()
      content = msg |> Map.get("content") |> extract_text_content()
      "[#{role}] #{content}"
    end)
    |> String.trim()
  end

  defp build_messages_block(_), do: ""

  defp extract_text_content(content) when is_binary(content), do: String.trim(content)

  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.map_join("\n", fn part ->
      cond do
        is_binary(part) ->
          part

        is_map(part) ->
          Map.get(part, "text", "")

        true ->
          ""
      end
    end)
    |> String.trim()
  end

  defp extract_text_content(_), do: ""

  defp extract_response_text(proxy_response) do
    response = Map.get(proxy_response, "response", %{})

    [
      get_in(response, ["content"]),
      get_in(response, ["reply_text"]),
      get_in(response, ["text"]),
      Map.get(proxy_response, "error")
    ]
    |> Enum.find_value("", fn value ->
      text = extract_text_content(value)
      if text == "", do: nil, else: text
    end)
  end
end
