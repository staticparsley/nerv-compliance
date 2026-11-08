require "test_helper"
require_relative "../support/scan_job_helper"

class ScansControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ScanJobHelper

  setup do
    @settings = Rails.configuration.x.scan_operations
    @old_username, @old_password = @settings.username, @settings.password
    @settings.username = "operator"
    @settings.password = "test-only-password"
  end

  teardown do
    @settings.username, @settings.password = @old_username, @old_password
  end

  test "manual trigger is disabled without configured operator credentials" do
    @settings.password = nil
    assert_no_enqueued_jobs do
      assert_no_difference "Scan.count" do
        post scans_path
        assert_response :forbidden
      end
    end
    get root_path
    assert_select "button[disabled]", text: "Run Assessment"
  end

  test "unauthenticated and incorrect credentials cannot trigger scans" do
    assert_no_enqueued_jobs do
      assert_no_difference "Scan.count" do
        post scans_path
        assert_response :unauthorized
        post scans_path, headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("operator", "incorrect") }
        assert_response :unauthorized
      end
    end
  end

  test "authorized POST only queues work and repeated POST reuses reservation" do
    with_pod_client do |calls|
      assert_enqueued_jobs 1, only: ComplianceScanJob do
        assert_difference "Scan.count", 1 do
          post scans_path, headers: operator_headers
          assert_response :see_other
          scan = Scan.last
          assert_redirected_to scan_path(scan)
          assert_equal "queued", scan.status
          assert_empty scan.checks
          post scans_path, headers: operator_headers
          assert_redirected_to scan_path(scan)
        end
      end
      assert_empty calls
    end
  end

  test "production trigger rejects HTTP even with valid credentials" do
    previous = Rails.env
    begin
      Rails.env = "production"
      assert_no_difference "Scan.count" do
        post scans_path, headers: operator_headers
        assert_response :forbidden
      end
    ensure
      Rails.env = previous
    end
  end

  test "CSRF token is required even with valid operator credentials" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      assert_no_difference "Scan.count" do
        post scans_path, headers: operator_headers
        assert_response :unprocessable_entity
      end
      get root_path
      token = response.parsed_body.at_css('meta[name="csrf-token"]')["content"]
      assert_difference "Scan.count" do
        post scans_path, headers: operator_headers.merge("X-CSRF-Token" => token)
        assert_response :see_other
      end
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
  end

  test "queue failure does not leave a queued scan" do
    callback = -> { throw :abort }
    ComplianceScanJob.set_callback(:enqueue, :before, callback)
    begin
      assert_no_difference "Scan.count" do
        post scans_path, headers: operator_headers
        assert_redirected_to scans_path
      end
      follow_redirect!
      assert_includes response.body, "Assessment could not be queued"
    ensure
      ComplianceScanJob.skip_callback(:enqueue, :before, callback)
    end
  end

  test "history paginates scans and shows control totals" do
    integration = Integration.create!(name: "history", provider: "kubernetes")
    scans = 21.times.map do
      Scan.create!(integration: integration, status: "completed", started_at: Time.current, completed_at: Time.current)
    end
    control = Control.create!(key: "test", title: "Test")
    scans.last.checks.create!(integration: integration, control: control, status: "fail")
    get scans_path
    assert_response :success
    assert_select "tbody tr", count: 20
    assert_select "a[href=?]", scans_path(page: 2)
    assert_select "tbody tr:first-child td:last-child", text: "0"
    assert_select "tbody tr:first-child td:nth-last-child(2)", text: "1"
    get scans_path(page: 2)
    assert_select "tbody tr", count: 1
    assert_select "a[href=?]", scan_path(scans.first)
  end

  test "scan details expose checks and escaped evidence with failed execution distinct from violations" do
    integration = Integration.create!(name: "history", provider: "kubernetes")
    scan = Scan.create!(integration: integration, status: "error", started_at: Time.current,
                        completed_at: Time.current, error_message: "K8S-003: TypeError")
    control = Control.create!(key: "K8S-001", title: "Privileged")
    check = scan.checks.create!(integration: integration, control: control, status: "fail", checked_at: Time.current)
    check.evidences.create!(resource: "test/pod", payload: { "container" => "<script>bad()</script>" })
    get scan_path(scan)
    assert_response :success
    assert_select ".execution-error", text: "FAILED"
    assert_select ".failed", text: "FAIL"
    assert_select "a[href=?]", assessment_path(check)
    assert_includes response.body, "test/pod"
    assert_includes response.body, "&lt;script&gt;"
    refute_includes response.body, "<script>bad()"
  end

  test "historical check detail remains accessible" do
    integration = Integration.create!(name: "history", provider: "kubernetes")
    control = Control.create!(key: "historical", title: "Historical")
    check = Check.create!(integration: integration, control: control, status: "pass", checked_at: Time.current)
    get assessment_path(check)
    assert_response :success
    assert_nil check.scan_id
    assert_includes response.body, "HISTORICAL"
  end

  test "dashboard shows latest queued scan and prevents duplicate button submissions" do
    scan = Compliance::ScanRequest.call
    get root_path
    assert_response :success
    assert_select "a[href=?]", scans_path
    assert_select "a[href=?]", scan_path(scan)
    assert_select "button[disabled]", text: "Run Assessment"
    assert_select ".pending", text: "QUEUED"
  end

  private

  def operator_headers
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(@settings.username, @settings.password) }
  end
end
