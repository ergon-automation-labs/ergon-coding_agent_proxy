defmodule BotArmyCodingAgentProxy.Application do
  @moduledoc """
  OTP application entrypoint for Coding Agent Proxy bot.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      []
      |> maybe_add_consumer()
      |> maybe_add_http()

    opts = [strategy: :one_for_one, name: BotArmyCodingAgentProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_consumer(children) do
    if Application.get_env(:bot_army_coding_agent_proxy, :start_consumer, true) do
      [{BotArmyCodingAgentProxy.NATS.Consumer, []} | children]
    else
      children
    end
  end

  defp maybe_add_http(children) do
    if Application.get_env(:bot_army_coding_agent_proxy, :start_http, true) do
      port =
        System.get_env("CODING_AGENT_PROXY_HTTP_PORT")
        |> case do
          nil -> Application.get_env(:bot_army_coding_agent_proxy, :http_port, 39_095)
          value -> String.to_integer(value)
        end

      [
        {Plug.Cowboy,
         scheme: :http,
         plug: BotArmyCodingAgentProxy.HTTP.Router,
         options: [ip: {0, 0, 0, 0}, port: port]}
        | children
      ]
    else
      children
    end
  end
end
