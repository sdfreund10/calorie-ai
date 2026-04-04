# frozen_string_literal: true

require "test_helper"

class MealSuggestionSchemaTest < ActiveSupport::TestCase
  test "Output is defined and matches schema property keys" do
    assert defined?(MealSuggestionSchema::Output), "expected MealSuggestionSchema::Output to be defined"
    assert_operator MealSuggestionSchema::Output, :<, Data
    assert_equal MealSuggestionSchema.properties.keys, MealSuggestionSchema::Output.members
  end

  test "serialize_output builds Output from a symbol-keyed hash" do
    content = {name: "Salad", calories: 350, note: "rough estimate"}
    result = MealSuggestionSchema.serialize_output(content)

    assert_instance_of MealSuggestionSchema::Output, result
    assert_equal "Salad", result.name
    assert_equal 350, result.calories
    assert_equal "rough estimate", result.note
  end

  test "serialize_output builds Output from a string-keyed hash" do
    content = {"name" => "Soup", "calories" => 200, "note" => nil}
    result = MealSuggestionSchema.serialize_output(content)

    assert_instance_of MealSuggestionSchema::Output, result
    assert_equal "Soup", result.name
    assert_equal 200, result.calories
    assert_nil result.note
  end

  test "serialize_output raises on invalid content type" do
    assert_raises(ArgumentError) do
      MealSuggestionSchema.serialize_output("")
    end

    assert_raises(ArgumentError) do
      MealSuggestionSchema.serialize_output(nil)
    end
  end

  test "serialize_output raises on missing required keys" do
    assert_raises(ArgumentError) do
      MealSuggestionSchema.serialize_output({})
    end

    assert_raises(ArgumentError) do
      MealSuggestionSchema.serialize_output({name: "Salas"}) # missing calories
    end
  end

  test "serialize_output sets default values for optional keys" do
    result = MealSuggestionSchema.serialize_output({name: "Salad", calories: 350})
    assert_equal "Salad", result.name
    assert_nil result.note
  end
end
