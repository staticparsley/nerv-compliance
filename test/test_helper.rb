ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # macOS's native pg/libpq stack can crash when Rails forks test workers.
    # Linux CI keeps process parallelism; PARALLEL_WORKERS can override either default.
    parallelize(workers: RUBY_PLATFORM.include?("darwin") ? 1 : :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
