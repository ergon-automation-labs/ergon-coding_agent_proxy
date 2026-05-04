import Config

config :bot_army_coding_agent_proxy,
  start_consumer: config_env() != :test,
  start_http: config_env() != :test,
  http_port: 39_095,
  http_token: System.get_env("BOT_ARMY_LLM_HTTP_TOKEN")
