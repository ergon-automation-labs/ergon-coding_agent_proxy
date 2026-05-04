defmodule BotArmyCodingAgentProxy.NATS.Consumer do
  use GenServer
  require Logger

  alias BotArmyRuntime.NATS.Connection
  alias BotArmyRuntime.NATS.Publisher

  @version Mix.Project.config()[:version]
  @registry_heartbeat_ms 20_000

  @subjects [
    %{
      subject: "coding_agent_proxy.chat.request",
      type: :request_reply,
      description: "Proxy coding-agent chat request to llm lane"
    }
  ]

  @llm_subject_by_lane %{
    "interactive" => "pi-go.llm.request.chat.interactive",
    "urgent" => "pi-go.llm.request.chat.urgent",
    "background" => "pi-go.llm.request.chat.background"
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def subject_for_lane(lane) do
    lane
    |> to_string()
    |> String.downcase()
    |> then(&Map.get(@llm_subject_by_lane, &1, @llm_subject_by_lane["interactive"]))
  end

  def build_forward_payload(payload) when is_map(payload) do
    %{
      "request_id" => Map.get(payload, "request_id", UUID.uuid4()),
      "request_type" => Map.get(payload, "request_type", "chat"),
      "prompt_context" => Map.get(payload, "prompt_context", %{}),
      "model_preference" => Map.get(payload, "model_preference", "auto"),
      "reply_subject" => Map.get(payload, "reply_subject", "coding_agent_proxy.llm.reply"),
      "timeout_ms" => Map.get(payload, "timeout_ms", 60_000),
      "tenant_id" => Map.get(payload, "tenant_id", "00000000-0000-0000-0000-000000000001"),
      "user_id" => Map.get(payload, "user_id")
    }
  end

  @impl true
  def init(_opts) do
    case GenServer.call(Connection, :get_connection, 5_000) do
      {:ok, conn} ->
        subscriptions =
          for %{subject: subject} <- @subjects do
            {Gnat.sub(conn, self(), subject), subject}
          end

        BotArmyRuntime.Registry.register("coding_agent_proxy", @subjects, @version)
        Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)

        Logger.info("[CodingAgentProxy.Consumer] subscribed to coding_agent_proxy.chat.request")

        {:ok, %{conn: conn, subscriptions: subscriptions, registry_registered?: true}}

      {:error, reason} ->
        Logger.error(
          "[CodingAgentProxy.Consumer] failed to get NATS connection: #{inspect(reason)}"
        )

        {:stop, :nats_connection_failed}
    end
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    payload =
      case Jason.decode(msg.body || "{}") do
        {:ok, data} when is_map(data) -> data
        _ -> %{}
      end

    route_message(msg.topic, payload, msg.reply_to)
    {:noreply, state}
  end

  def handle_info(:registry_heartbeat, state) do
    if state.registry_registered? do
      BotArmyRuntime.Registry.register("coding_agent_proxy", @subjects, @version)
      Process.send_after(self(), :registry_heartbeat, @registry_heartbeat_ms)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp route_message("coding_agent_proxy.chat.request", payload, reply_to) do
    lane = payload |> Map.get("lane", "interactive") |> to_string() |> String.downcase()
    llm_subject = subject_for_lane(lane)
    llm_payload = build_forward_payload(payload)

    timeout_ms = llm_payload["timeout_ms"] || 60_000

    case Publisher.request(llm_subject, llm_payload, timeout_ms: timeout_ms) do
      {:ok, response} ->
        send_reply(reply_to, %{
          "ok" => true,
          "subject" => llm_subject,
          "lane" => lane,
          "response" => response
        })

      {:error, reason} ->
        send_reply(reply_to, %{
          "ok" => false,
          "subject" => llm_subject,
          "lane" => lane,
          "error" => inspect(reason)
        })
    end
  end

  defp route_message(_unknown, _payload, reply_to) do
    send_reply(reply_to, %{"ok" => false, "error" => "unknown subject"})
  end

  defp send_reply(nil, _payload), do: :ok

  defp send_reply(reply_to, payload) do
    case Publisher.publish(reply_to, payload) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("[CodingAgentProxy.Consumer] failed to publish reply: #{inspect(reason)}")
    end
  end
end
