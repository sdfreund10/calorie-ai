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

    # Add more helper methods to be used by all tests here...
  end
end
