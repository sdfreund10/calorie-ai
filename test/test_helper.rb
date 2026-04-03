ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Temporarily replace a class method (e.g. to stub external services).
    def with_stubbed_class_method(klass, method_name, implementation)
      singleton = klass.singleton_class
      original = singleton.instance_method(method_name)
      singleton.send(:define_method, method_name, implementation)
      yield
    ensure
      singleton.send(:define_method, method_name, original)
    end

    # Add more helper methods to be used by all tests here...
  end
end
