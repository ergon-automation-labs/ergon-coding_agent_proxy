defmodule BotArmyCodingAgentProxy.HTTP.Router do
  @moduledoc """
  Anthropic-compatible HTTP facade for coding agent clients.
  """

  use Plug.Router
  require Logger

  alias BotArmyCodingAgentProxy.HTTP.Adapter
  alias BotArmyCodingAgentProxy.NATS.Consumer
  alias BotArmyRuntime.NATS.Publisher

  plug(Plug.Logger)
  plug(Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason)
  plug(:match)
  plug(:dispatch)

  post "/v1/messages" do
    with :ok <- authorize(conn),
         body <- conn.body_params,
         payload <- Adapter.build_proxy_payload(body),
         forward <- Consumer.build_forward_payload(payload),
         lane <- Map.get(payload, "lane", "interactive"),
         subject <- Consumer.subject_for_lane(lane),
         timeout_ms <- Map.get(forward, "timeout_ms", 60_000),
         {:ok, response} <- Publisher.request(subject, forward, timeout_ms: timeout_ms) do
      requested_model = Map.get(body, "model")
      anthropic = Adapter.build_anthropic_response(response, requested_model)
      send_json(conn, 200, anthropic)
    else
      {:error, reason} ->
        Logger.warning("[CodingAgentProxy.HTTP] NATS request failed: #{inspect(reason)}")
        send_json(conn, 502, %{"error" => "upstream_nats_failure", "detail" => inspect(reason)})

      {:unauthorized, reason} ->
        send_json(conn, 401, %{"error" => "unauthorized", "detail" => reason})
    end
  end

  match _ do
    send_json(conn, 404, %{"error" => "not_found"})
  end

  defp send_json(conn, status, payload) do
    body = Jason.encode!(payload)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp authorize(conn) do
    expected = Application.get_env(:bot_army_coding_agent_proxy, :http_token)

    if is_binary(expected) and String.trim(expected) != "" do
      provided =
        conn
        |> Plug.Conn.get_req_header("authorization")
        |> List.first()
        |> to_string()
        |> String.replace_prefix("Bearer ", "")
        |> String.trim()

      if provided == String.trim(expected) do
        :ok
      else
        {:unauthorized, "missing or invalid bearer token"}
      end
    else
      :ok
    end
  end
end
