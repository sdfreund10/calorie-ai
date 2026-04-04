ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def with_stubbed_instance_method(klass, method_name, implementation)
      klass.class_eval do
        alias_method :"__stub_orig_#{method_name}", method_name
        define_method(method_name, implementation)
      end
      yield
    ensure
      klass.class_eval do
        alias_method method_name, :"__stub_orig_#{method_name}"
        remove_method :"__stub_orig_#{method_name}"
      end
    end

    # Stubs FoodPhotoAnalyzer#call to return a Result built like production (serialized schema output).
    # Pass a primitive +content+ hash; only MealSuggestionSchema::Output keys are kept.
    #
    # @param success [Boolean]
    # @param content [Hash, nil] merged into defaults { name, calories, note } when success; ignored when not
    # @param error_message [String, nil]
    # @param model [String, nil] defaults to "test" on success and nil on failure when omitted
    def stub_food_photo_analyzer_call(success: true, content: nil, error_message: nil, model: nil)
      result = build_food_photo_analyzer_stub_result(
        success: success,
        content: content,
        error_message: error_message,
        model: model
      )
      with_stubbed_instance_method(FoodPhotoAnalyzer, :call, ->(*) { result }) { yield }
    end

    def refute_food_photo_analyzer_called(reason = "FoodPhotoAnalyzer#call should not run")
      with_stubbed_instance_method(FoodPhotoAnalyzer, :call, ->(*) { flunk(reason) }) { yield }
    end

    # Add more helper methods to be used by all tests here...

    private

    def build_food_photo_analyzer_stub_result(success:, content:, error_message:, model:)
      resolved_model = if model.nil?
        success ? "test" : nil
      else
        model
      end

      attributes = if success
        defaults = {name: "Stub meal", calories: 100, note: nil}
        allowed = MealSuggestionSchema::Output.members
        sliced = (content || {}).to_h.symbolize_keys.slice(*allowed)
        MealSuggestionSchema.serialize_output(defaults.merge(sliced))
      end

      FoodPhotoAnalyzer::Result.new(
        success: success,
        attributes: attributes,
        error_message: error_message,
        model: resolved_model
      )
    end
  end
end
