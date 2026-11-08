require "test_helper"
require "fugit"

class ScheduledAssessmentJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "scheduler reserves through the same path as manual requests" do
    assert_enqueued_jobs 1, only: ComplianceScanJob do
      ScheduledAssessmentJob.perform_now
      ScheduledAssessmentJob.perform_now
    end
    assert_equal 1, Scan.active.count
    assert_equal "queued", Scan.active.sole.status
  end

  test "scheduler skips a running scan" do
    scan, = Scan.reserve(status: "running")
    assert_no_enqueued_jobs do
      assert_no_difference "Scan.count" do
        ScheduledAssessmentJob.perform_now
      end
    end
    assert_equal "running", scan.reload.status
  end

  test "recurring configuration defaults to six hours and permits override or disable" do
    with_schedule_environment do
      config = recurring_config
      %w[development production].each do |environment|
        task = config.fetch(environment).fetch("compliance_assessment")
        assert_equal "ScheduledAssessmentJob", task.fetch("class")
        schedule = Fugit.parse(task.fetch("schedule"))
        first = schedule.next_time(Time.utc(2026, 11, 9))
        assert_equal 6.hours, schedule.next_time(first).to_i - first.to_i
      end
      ENV["NERV_SCAN_SCHEDULE"] = "every 2 hours"
      assert_equal "every 2 hours", recurring_config.dig("production", "compliance_assessment", "schedule")
      ENV["NERV_SCHEDULED_SCANS_ENABLED"] = "false"
      assert_nil recurring_config.dig("development", "compliance_assessment")
      assert_nil recurring_config.dig("production", "compliance_assessment")
    end
  end

  private

  def recurring_config
    YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
  end

  def with_schedule_environment
    keys = %w[NERV_SCAN_SCHEDULE NERV_SCHEDULED_SCANS_ENABLED]
    previous = keys.to_h { |key| [ key, ENV.delete(key) ] }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
