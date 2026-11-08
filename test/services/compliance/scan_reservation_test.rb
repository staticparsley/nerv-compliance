require "test_helper"

class ScanReservationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous connections reserve only one active scan" do
    integration = Integration.create!(name: "NERV Kubernetes", provider: "kubernetes")
    gate = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          Scan.reserve
        end
      end
    end
    2.times { gate << true }
    results = threads.map(&:value)
    assert_equal 1, results.map { |scan, _created| scan.id }.uniq.length
    assert_equal [ false, true ], results.map(&:last).sort_by(&:to_s)
    assert_equal 1, Scan.active.count
  ensure
    threads&.each(&:join)
    integration&.scans&.destroy_all
    integration&.destroy!
  end
end
