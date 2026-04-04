# frozen_string_literal: true

require "ruby_llm/schema"

# RubyLLM structured output schema for vision-based meal suggestions.
class MealSuggestionSchema < RubyLLM::Schema
  description "Meal log values inferred from a food photo"

  string :name,
    description: "Short dish or food name",
    max_length: 80

  integer :calories,
    description: "Estimated total calories for the visible portion",
    required: true

  string :note,
    description: "Optional notes, caveats, or uncertainty about the estimate",
    required: false

  Output = Data.define(*properties.keys)
  def self.serialize_output(content)
    attrs = content.to_h.symbolize_keys

    # validate required keys
    required_keys = required_properties # [:name, :calories]
    missing_keys = required_keys - attrs.keys
    if missing_keys.any?
      raise ArgumentError, "missing required keys: #{missing_keys.join(", ")}"
    end

    # set default values for optional keys
    merged = optional_properties.to_h { |k| [k, nil] }.merge(attrs)

    # return structured output object
    Output.new(**merged)
  rescue NoMethodError => e
    # handle no method errors from non-Hash objects
    if e.message.include?("undefined method 'to_h'")
      raise ArgumentError, "expected a Hash or object responding to #to_h, got #{content.class.name}"
    else
      raise e
    end
  end

  def self.optional_properties
    # dsl provided by ruby_llm-schema
    properties.keys - required_properties
  end
  private_class_method :optional_properties
end
