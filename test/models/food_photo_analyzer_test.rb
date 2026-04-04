# frozen_string_literal: true

require "test_helper"

class FoodPhotoAnalyzerTest < ActiveSupport::TestCase
  test "returns failure when image path does not exist" do
    result = FoodPhotoAnalyzer.new(image_path: "/nonexistent/meal.png").call

    assert_not result.success
    assert_equal({}, result.attributes)
    assert_match(/not available/i, result.error_message)
    assert_nil result.model
  end

  test "returns success with serialized attributes when LLM responds" do
    llm_response = {name: "Rice bowl", calories: 520, note: "estimate"}

    with_stubbed_llm_returning(llm_response) do
      with_temp_image_file do |path|
        result = FoodPhotoAnalyzer.new(image_path: path, user_description: "lunch").call

        assert result.success
        assert_instance_of MealSuggestionSchema::Output, result.attributes
        assert_equal "Rice bowl", result.attributes.name
        assert_equal 520, result.attributes.calories
        assert_equal "estimate", result.attributes.note
        assert_equal RubyLLM.config.default_model, result.model
      end
    end
  end

  test "passes user description and image path to the LLM client" do
    llm_response = {name: "x", calories: 1, note: nil}
    fake = FakeLlmClient.new(llm_response)

    with_stubbed_instance_method(FoodPhotoAnalyzer, :llm_client, -> { fake }) do
      with_temp_image_file do |path|
        FoodPhotoAnalyzer.new(image_path: path, user_description: "vegan").call

        assert_equal "vegan", fake.captured_prompt
        assert_equal path, fake.captured_image_path
      end
    end
  end

  test "uses explicit model_id in result when provided" do
    llm_response = {name: "x", calories: 1, note: nil}

    with_stubbed_llm_returning(llm_response) do
      with_temp_image_file do |path|
        result = FoodPhotoAnalyzer.new(image_path: path, model_id: "gpt-4o-mini").call

        assert result.success
        assert_equal "gpt-4o-mini", result.model
      end
    end
  end

  test "returns failure with safe message when RubyLLM raises" do
    assert_error_result(RubyLLM::Error.new("upstream failure"))
  end

  test "returns failure with safe message when Faraday raises" do
    assert_error_result(Faraday::TimeoutError.new(nil))
  end

  test "returns failure with safe message when IOError is raised" do
    assert_error_result(IOError.new("read failed"))
  end

  private

  class FakeLlmClient
    attr_reader :captured_prompt, :captured_image_path

    def initialize(response_content)
      @response_content = response_content
    end

    def chat
      self
    end

    def with_model(model_id)
      self
    end

    def with_schema(schema)
      self
    end

    def with_instructions(instructions)
      self
    end

    def ask(prompt, with:)
      @captured_prompt = prompt
      @captured_image_path = with
      Struct.new(:content).new(@response_content)
    end
  end

  def with_stubbed_llm_returning(content)
    fake = FakeLlmClient.new(content)
    with_stubbed_instance_method(FoodPhotoAnalyzer, :llm_client, -> { fake }) do
      yield
    end
  end

  def with_temp_image_file
    Tempfile.create(["meal", ".png"]) do |f|
      f.binmode
      f.write("fake_png_bytes")
      f.rewind
      yield f.path
    end
  end

  def assert_error_result(exception)
    with_stubbed_instance_method(FoodPhotoAnalyzer, :llm_client, -> { raise exception }) do
      with_temp_image_file do |path|
        result = FoodPhotoAnalyzer.new(image_path: path).call

        assert_not result.success
        assert_nil result.attributes
        assert_match(/try again|manually/i, result.error_message)
      end
    end
  end
end
