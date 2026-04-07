# frozen_string_literal: true

# Calls a vision-capable RubyLLM model with MealSuggestionSchema. Returns a simple result object.
class FoodPhotoAnalyzer
  Result = Data.define(:success, :attributes, :error_message, :model, :token_usage)

  SYSTEM_INSTRUCTIONS = <<~TEXT.squish.freeze
    You help users log meals in a calorie tracking app. A user will provide you a photo of their meal
    and optionally a description of what they ate. Your goal is to identify the food and estimate the calories.

    ## STEPS
    1. Identify the food in the photos and described by the user.
    2. Estimate the calories of a single portion.
    3. Estimate the approximate portion based on the user's description and food displayed in the photo.
    4. Compute the approximate calories and return the results.

    ## FURTHER INSTRUCTIONS
    - Pay careful attention to the user's description when estimate the portion size.
    - Without user text, estimate a single reasonable serving of the main food in focus.
    - Estimate conservatively using standard servings.
  TEXT

  OUTPUT_SCHEMA = MealSuggestionSchema

  attr_reader :token_usage

  def initialize(image_path:, user_description: nil, model_id: nil)
    @image_path = image_path
    @user_description = user_description
    @model_id = model_id.presence
    @token_usage = {input: 0, output: 0}
  end

  def call
    unless File.file?(@image_path)
      return failed_result("Image file is not available.")
    end

    response = llm_chat.ask(@user_description, with: @image_path)
    log_token_usage(response)
    Result.new(
      success: true,
      attributes: OUTPUT_SCHEMA.serialize_output(response.content),
      error_message: nil,
      model: model_id,
      token_usage: @token_usage.dup
    )
  rescue RubyLLM::Error, Faraday::Error, IOError, SystemCallError => e
    failed_result(safe_error(e))
  end

  def model_id
    @model_id.presence || RubyLLM.config.default_model
  end

  private

  # separate llm_client and llm_chat for stubbing with fake client in tests
  # could move to an initialization param if needed
  def llm_client
    RubyLLM.chat
  end

  def llm_chat
    chat = llm_client
    chat = chat.with_model(@model_id) if @model_id.present?
    chat.with_schema(OUTPUT_SCHEMA).with_instructions(SYSTEM_INSTRUCTIONS)
  end

  def safe_error(error)
    Rails.logger.warn("[FoodPhotoAnalyzer] #{error.class}: #{error.message}")
    "Could not analyze the photo. Please try again or enter details manually."
  end

  def failed_result(error_message)
    Result.new(success: false, attributes: nil, error_message: error_message, model: nil, token_usage: nil)
  end

  def log_token_usage(response)
    @token_usage[:input] = response.input_tokens
    @token_usage[:output] = response.output_tokens
  end
end
