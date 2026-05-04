defmodule BotArmyCodingAgentProxy.Application do
  @moduledoc """
  OTP application entrypoint for Coding Agent Proxy bot.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:bot_army_coding_agent_proxy, :start_consumer, true) do
        [{BotArmyCodingAgentProxy.NATS.Consumer, []}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: BotArmyCodingAgentProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
