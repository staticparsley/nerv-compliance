require "test_helper"
require_relative "../../support/pod_fixture"

class CheckRunnerTest < ActiveSupport::TestCase
  include PodFixture

  test "creates a running scan before fetching once and persists all results" do
    calls = 0
    pod = pod_fixture
    client = Object.new
    client.define_singleton_method(:list_pods) do
      calls += 1
      scan = Scan.order(:id).last
      raise "not running" unless scan.status == "running" && scan.completed_at.nil?
      [ pod ]
    end
    scan = nil
    assert_difference [ "Scan.count", "Integration.count" ], 1 do
      assert_difference [ "Check.count", "Evidence.count" ], 3 do
        scan = Compliance::CheckRunner.new(pod_client: client).call
      end
    end
    assert_equal 1, calls
    assert_equal "completed", scan.status
    assert_operator scan.completed_at, :>=, scan.started_at
    assert_nil scan.error_message
    assert_equal %w[pass pass pass], scan.checks.order(:id).pluck(:status)
    scan.checks.each do |check|
      assert_equal scan.integration, check.integration
      assert_equal 1, check.evidences.sole.payload["pods_scanned"]
    end
  end

  test "findings persist with summaries and failed compliance still completes execution" do
    pod = pod_fixture
    pod["spec"]["containers"][0]["securityContext"]["privileged"] = true
    scan = run_with([ pod ])
    assert_equal "completed", scan.status
    check = scan.checks.joins(:control).find_by!(controls: { key: "K8S-001" })
    assert_equal "fail", check.status
    assert_equal 2, check.evidences.count
    assert_equal true, check.evidences.find_by!(resource: "test/unit-01").payload["privileged"]
  end

  test "API failures record errors for every control without retaining sensitive exception messages" do
    client = Object.new
    client.define_singleton_method(:list_pods) { raise IOError, "secret-token" }
    scan = Compliance::CheckRunner.new(pod_client: client).call
    assert_equal "error", scan.status
    assert scan.completed_at
    assert_equal %w[error error error], scan.checks.pluck(:status)
    assert_equal 0, Evidence.where(check: scan.checks).count
    assert_includes scan.error_message, "IOError"
    refute_includes scan.error_message, "secret-token"
  end

  test "partial evaluation failures preserve successful checks" do
    pod = pod_fixture
    pod["spec"]["containers"][0]["resources"] = false
    scan = run_with([ pod ])
    assert_equal "error", scan.status
    assert_equal %w[pass pass error], scan.checks.order(:id).pluck(:status)
    assert_equal 2, Evidence.where(check: scan.checks).count
    assert_includes scan.error_message, "K8S-003"
  end

  test "invalid API payload never passes" do
    scan = run_with(nil)
    assert_equal "error", scan.status
    assert_equal %w[error error error], scan.checks.pluck(:status)
  end

  test "existing checks and evidence survive subsequent scans without a scan backfill" do
    integration = Integration.create!(name: "Historical", provider: "kubernetes")
    control = Control.create!(key: "legacy")
    check = Check.create!(control: control, integration: integration, status: "pass")
    evidence = check.evidences.create!(resource: "legacy", payload: { "retained" => true })
    run_with([])
    assert_nil check.reload.scan_id
    assert_equal({ "retained" => true }, evidence.reload.payload)
  end

  test "evidence persistence failure rolls back the check before recording an error" do
    callback = -> { raise ActiveRecord::RecordInvalid, self if resource == "test/unit-01" }
    Evidence.set_callback(:create, :before, callback)
    begin
      pod = pod_fixture
      pod["spec"]["containers"][0]["securityContext"]["privileged"] = true
      scan = run_with([ pod ])
      assert_equal "error", scan.status
      assert_equal %w[error pass pass], scan.checks.order(:id).pluck(:status)
      assert_equal 2, Evidence.where(check: scan.checks).count
      assert_empty scan.checks.find_by!(status: "error").evidences
    ensure
      Evidence.skip_callback(:create, :before, callback)
    end
  end

  test "unexpected persistence failure marks the scan errored and propagates" do
    callback = -> { raise ActiveRecord::RecordInvalid, self }
    Control.set_callback(:create, :before, callback)
    begin
      assert_raises(ActiveRecord::RecordInvalid) { run_with([]) }
      scan = Scan.order(:id).last
      assert_equal "error", scan.status
      assert scan.completed_at
      assert_includes scan.error_message, "ActiveRecord::RecordInvalid"
      assert_empty scan.checks
    ensure
      Control.skip_callback(:create, :before, callback)
    end
  end

  private

  def run_with(pods)
    client = Object.new
    client.define_singleton_method(:list_pods) { pods }
    Compliance::CheckRunner.new(pod_client: client).call
  end
end
