# frozen_string_literal: true

require "test_helper"

class MealPhotoSuggestionServiceTest < ActiveSupport::TestCase
  test "returns failure when image path does not exist" do
    result = MealPhotoSuggestionService.call(image_path: "/nonexistent/meal.png")

    assert_not result.success
    assert_match(/not available/i, result.error_message)
  end

  test "returns normalized attributes when LLM responds with structured content" do
    png = Rails.root.join("test/fixtures/files/one_pixel.png")
    response = Struct.new(:content).new({
      "name" => "  Bowl  ",
      "meal" => "LUNCH",
      "calories" => 420,
      "note" => "estimate"
    })

    fake_chat = Object.new
    def fake_chat.with_model(*) self end
    def fake_chat.with_schema(*) self end
    def fake_chat.with_instructions(*) self end
    def fake_chat.ask(*, **) @response end
    fake_chat.instance_variable_set(:@response, response)

    with_stubbed_class_method(RubyLLM, :chat, ->(*) { fake_chat }) do
      Tempfile.create([ "meal", ".png" ]) do |f|
        f.binmode
        f.write(File.binread(png))
        f.rewind
        result = MealPhotoSuggestionService.new(image_path: f.path, model_id: "gpt-4o-mini").call

        assert result.success
        assert_equal "Bowl", result.attributes[:name]
        assert_equal "lunch", result.attributes[:meal]
        assert_equal 420, result.attributes[:calories]
        assert_equal "estimate", result.attributes[:note]
      end
    end
  end
end
