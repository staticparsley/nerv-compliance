require "test_helper"
require_relative "../support/finding_fixture"

class FindingsControllerTest < ActionDispatch::IntegrationTest
  include FindingFixture

  test "filters distinguish open accepted and resolved findings without changing raw failures" do
    finding = observed_finding
    accept_finding(finding)
    get findings_path
    assert_response :success
    assert_select "tbody tr", count: 2
    get findings_path(status: "accepted_risk", control_id: finding.control_id, namespace: finding.namespace)
    assert_select "tbody tr", count: 1
    assert_select ".accepted-risk", text: "ACCEPTED RISK"
    get findings_path(status: "all", namespace: "not-present")
    assert_select "tbody tr", count: 0
    run_pods([])
    get findings_path(status: "resolved")
    assert_select "tbody tr", count: 3
    get findings_path(status: "not-a-status")
    assert_select "tbody tr", count: 0
  end

  test "finding details show evidence audit decisions and separate raw failures" do
    finding = observed_finding
    acceptance = accept_finding(finding, reason: "<script>must be escaped</script>")
    get finding_path(finding)
    assert_response :success
    assert_includes response.body, "operator"
    assert_includes response.body, acceptance.expires_on.to_s
    assert_includes response.body, "&lt;script&gt;"
    refute_includes response.body, "<script>must be escaped"
    evidence = finding.evidences.sole
    assert_select "a[href=?]", assessment_path(evidence.check)
    assert_includes response.body, "FAIL"
    assert_includes response.body, "uid-01"
  end

  test "dashboard counts accepted risks separately from open violations and raw control failures" do
    finding = observed_finding
    accept_finding(finding)
    get root_path
    assert_response :success
    assert_select ".finding-counts .danger", text: "2"
    assert_select ".finding-counts .accepted-text", text: "1"
    assert_select ".control-matrix .failed", count: 3
    assert_select "a[href=?]", findings_path
  end

  test "finding list paginates with filters preserved" do
    pods = 8.times.map do |index|
      pod = violating_pod(uid: "uid-#{index}")
      pod["metadata"]["name"] = "pod-#{index}"
      pod
    end
    run_pods(pods)
    get findings_path(status: "open", namespace: "test")
    assert_select "tbody tr", count: 20
    assert_select "a[href*='page=2']", count: 1
    get findings_path(status: "open", namespace: "test", page: 2)
    assert_select "tbody tr", count: 4
  end
end
