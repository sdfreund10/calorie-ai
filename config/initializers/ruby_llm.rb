# frozen_string_literal: true

RubyLLM.configure do |config|
  # config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.default_model = "claude-haiku-4-5"
end
