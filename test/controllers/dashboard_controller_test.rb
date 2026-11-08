require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get dashboard_index_url
    assert_response :success
  end
  test "error assessments show unknown compliance" do
    integration = Integration.create!(name: "test", provider: "kubernetes")
    control = Control.create!(key: "K8S-001", title: "No privileged containers")
    check = Check.create!(integration: integration, control: control, status: "error", checked_at: Time.current)
    get assessment_path(check)
    assert_response :success
    assert_includes response.body, "EVALUATION UNAVAILABLE // COMPLIANCE UNKNOWN"
    refute_includes response.body, "NO VIOLATIONS RECORDED"
  end
end
