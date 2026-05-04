defmodule BotArmyCodingAgentProxy.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Mix.env() == :test do
        []
      else
        [{BotArmyCodingAgentProxy.NATS.Consumer, []}]
      end

    opts = [strategy: :one_for_one, name: BotArmyCodingAgentProxy.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
