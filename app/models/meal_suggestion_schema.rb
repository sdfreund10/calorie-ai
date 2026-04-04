# frozen_string_literal: true

require "ruby_llm/schema"

# RubyLLM structured output schema for vision-based meal suggestions.
class MealSuggestionSchema < RubyLLM::Schema
  description "Meal log values inferred from a food photo"

  string :name,
    description: "Short dish or food name",
    required: false,
    max_length: 80

  integer :calories,
    description: "Estimated total calories for the visible portion",
    required: true

  string :note,
    description: "Optional notes, caveats, or uncertainty about the estimate",
    required: false
end
