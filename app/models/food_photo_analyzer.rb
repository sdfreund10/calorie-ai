# frozen_string_literal: true

# Calls a vision-capable RubyLLM model with MealSuggestionSchema. Returns a simple result object.
class FoodPhotoAnalyzer
  Result = Data.define(:success, :attributes, :error_message, :model)

  SYSTEM_INSTRUCTIONS = <<~TEXT.squish.freeze
    You help users log meals in a calorie tracking app. From the photo (and optional user text),
    estimate name, meal type, total calories, and a short note if helpful.
    Be conservative with portion sizes. Use the user's optional description as extra context.
    If the meal time is unclear, use other for meal.
  TEXT

  OUTPUT_SCHEMA = MealSuggestionSchema

  def initialize(image_path:, user_description: nil, model_id: nil)
    @image_path = image_path
    @user_description = user_description
    @model_id = model_id.presence
  end

  def call
    unless File.file?(@image_path)
      return Result.new(success: false, attributes: {}, error_message: "Image file is not available.", model: nil)
    end

    response = llm_chat.ask(@user_description, with: @image_path)
    Result.new(
      success: true,
      attributes: OUTPUT_SCHEMA.serialize_output(response.content),
      error_message: nil,
      model: model_id
    )
  rescue RubyLLM::Error, Faraday::Error, IOError, SystemCallError => e
    Result.new(success: false, attributes: nil, error_message: safe_error(e), model: model_id)
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
end
