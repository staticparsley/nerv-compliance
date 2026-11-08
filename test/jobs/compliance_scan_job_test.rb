require "test_helper"
require_relative "../support/scan_job_helper"
require_relative "../support/pod_fixture"

class ComplianceScanJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ScanJobHelper
  include PodFixture

  test "queued scan executes once and persists associated checks" do
    with_pod_client(pods: [ pod_fixture ]) do |calls|
      scan = Compliance::ScanRequest.call
      assert_equal "queued", scan.status
      assert_nil scan.started_at
      assert_empty calls
      assert_enqueued_with(job: ComplianceScanJob, args: [ scan.id ])
      ComplianceScanJob.perform_now(scan.id)
      assert_equal "completed", scan.reload.status
      assert scan.started_at
      assert scan.completed_at
      assert_equal 3, scan.checks.count
      assert_equal 3, Evidence.where(check: scan.checks).count
      ComplianceScanJob.perform_now(scan.id)
      assert_equal 1, calls.length
      assert_equal 3, scan.checks.count
    end
  end

  test "duplicate delivery while running never contacts Kubernetes" do
    scan = Compliance::ScanRequest.call
    scan.update!(status: "running", started_at: Time.current)
    with_pod_client do |calls|
      ComplianceScanJob.perform_now(scan.id)
      assert_empty calls
      assert_equal "running", scan.reload.status
      assert_empty scan.checks
    end
  end

  test "API failures mark the scan and all controls as errors without exposing tokens" do
    with_pod_client(error: IOError.new("service-account-secret")) do
      scan = Compliance::ScanRequest.call
      ComplianceScanJob.perform_now(scan.id)
      assert_equal "error", scan.reload.status
      assert_equal %w[error error error], scan.checks.pluck(:status)
      refute_includes scan.error_message, "service-account-secret"
      assert scan.completed_at
    end
  end

  test "partial failures retain other control results" do
    pod = pod_fixture
    pod["spec"]["containers"][0]["resources"] = false
    with_pod_client(pods: [ pod ]) do
      scan = Compliance::ScanRequest.call
      ComplianceScanJob.perform_now(scan.id)
      assert_equal "error", scan.reload.status
      assert_equal %w[pass pass error], scan.checks.order(:id).pluck(:status)
    end
  end

  test "direct runner does not bypass queued scan reservation" do
    scan = Compliance::ScanRequest.call
    with_pod_client do |calls|
      assert_equal scan, Compliance::CheckRunner.new.call
      assert_empty calls
      assert_equal "queued", scan.reload.status
    end
  end

  test "repeat requests reuse queued and running scans without another job" do
    scan = Compliance::ScanRequest.call
    assert_no_enqueued_jobs do
      assert_no_difference "Scan.count" do
        assert_equal scan, Compliance::ScanRequest.call
        scan.update!(status: "running", started_at: Time.current)
        assert_equal scan, Compliance::ScanRequest.call
      end
    end
  end

  test "new requests are allowed after a completed or failed execution" do
    scan = Compliance::ScanRequest.call
    scan.update!(status: "error", started_at: Time.current, completed_at: Time.current, error_message: "Unavailable")
    assert_difference "Scan.count" do
      assert_not_equal scan, Compliance::ScanRequest.call
    end
  end

  test "database rejects a second active scan" do
    scan = Compliance::ScanRequest.call
    assert_raises ActiveRecord::RecordNotUnique do
      Scan.transaction(requires_new: true) do
        Scan.create!(integration: scan.integration, status: "queued")
      end
    end
  end

  test "enqueue abort rolls back reservation" do
    callback = -> { throw :abort }
    ComplianceScanJob.set_callback(:enqueue, :before, callback)
    begin
      assert_no_difference "Scan.count" do
        assert_raises(ActiveJob::EnqueueError) { Compliance::ScanRequest.call }
      end
    ensure
      ComplianceScanJob.skip_callback(:enqueue, :before, callback)
    end
  end

  test "Solid Queue persists scan and job atomically in the same database" do
    previous = ComplianceScanJob.queue_adapter
    ComplianceScanJob.queue_adapter = :solid_queue
    begin
      assert_equal Scan.connection_pool, SolidQueue::Record.connection_pool
      assert_difference [ "Scan.count", "SolidQueue::Job.count", "SolidQueue::ReadyExecution.count" ] do
        scan = Compliance::ScanRequest.call
        job = SolidQueue::Job.order(:id).last
        assert_equal [ scan.id ], job.arguments["arguments"]
      end
      # A failure after inserting the queue row must roll back both records.
      Scan.active.first.update!(status: "error", started_at: Time.current,
                               completed_at: Time.current, error_message: "Test finished")
      callback = -> { raise ActiveJob::EnqueueError, "Unavailable" }
      ComplianceScanJob.set_callback(:enqueue, :after, callback)
      begin
        assert_no_difference [ "Scan.count", "SolidQueue::Job.count" ] do
          assert_raises(ActiveJob::EnqueueError) { Compliance::ScanRequest.call }
        end
      ensure
        ComplianceScanJob.skip_callback(:enqueue, :after, callback)
      end
    ensure
      ComplianceScanJob.queue_adapter = previous
    end
  end
end
