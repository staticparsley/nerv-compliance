require "test_helper"
require_relative "../support/finding_fixture"

class RiskAcceptancesControllerTest < ActionDispatch::IntegrationTest
  include FindingFixture

  setup do
    @settings = Rails.configuration.x.scan_operations
    @previous = [ @settings.username, @settings.password ]
    @settings.username, @settings.password = "risk-operator", "test-only-password"
    @finding = observed_finding
  end

  teardown do
    @settings.username, @settings.password = @previous
  end

  test "unconfigured credentials disable the mutation and hide its form" do
    @settings.password = nil
    assert_no_difference "RiskAcceptance.count" do
      post finding_risk_acceptances_path(@finding), params: input
      assert_response :forbidden
    end
    get finding_path(@finding)
    assert_select "form[action=?]", finding_risk_acceptances_path(@finding), count: 0
    assert_includes response.body, "RISK ACCEPTANCE DISABLED"
  end

  test "unauthenticated and unauthorized requests cannot accept risk" do
    assert_no_difference "RiskAcceptance.count" do
      post finding_risk_acceptances_path(@finding), params: input
      assert_response :unauthorized
      post finding_risk_acceptances_path(@finding), params: input,
        headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("wrong", "wrong") }
      assert_response :unauthorized
    end
  end

  test "authorized acceptance uses authenticated actor and leaves historical results intact" do
    evidence = @finding.evidences.sole
    snapshot = [ evidence.attributes, evidence.check.attributes ]
    assert_difference "RiskAcceptance.count", 1 do
      post finding_risk_acceptances_path(@finding), params: input.deep_merge(risk_acceptance: { accepted_by: "spoofed", finding_id: 999 }), headers: headers
      assert_redirected_to finding_path(@finding)
    end
    assert_equal "accepted_risk", @finding.reload.status
    assert_equal "risk-operator", @finding.current_risk_acceptance.accepted_by
    assert_equal snapshot, [ evidence.reload.attributes, evidence.check.reload.attributes ]
  end

  test "invalid acceptance is rejected with no audit or status change" do
    assert_no_difference "RiskAcceptance.count" do
      post finding_risk_acceptances_path(@finding), params: { risk_acceptance: { reason: "", expires_on: Date.yesterday } }, headers: headers
      assert_redirected_to finding_path(@finding)
    end
    follow_redirect!
    assert_includes response.body, "Reason"
    assert_equal "open", @finding.reload.status
  end

  test "expiration is reflected in list and dashboard without a worker" do
    accept_finding(@finding, expires_on: Time.current.utc.to_date + 1)
    travel 2.days
    get findings_path(status: "accepted_risk")
    assert_select "tbody tr", count: 0
    get findings_path(status: "open")
    assert_select "tbody tr", count: 3
    get root_path
    assert_select ".finding-counts .accepted-text", text: "0"
    assert_select ".finding-counts .danger", text: "3"
  end

  test "CSRF protection applies even with correct credentials" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      assert_no_difference "RiskAcceptance.count" do
        post finding_risk_acceptances_path(@finding), params: input, headers: headers
        assert_response :unprocessable_entity
      end
      get finding_path(@finding)
      token = response.parsed_body.at_css('meta[name="csrf-token"]')["content"]
      assert_difference "RiskAcceptance.count" do
        post finding_risk_acceptances_path(@finding), params: input, headers: headers.merge("X-CSRF-Token" => token)
        assert_response :see_other
      end
    ensure
      ActionController::Base.allow_forgery_protection = original
    end
  end

  test "production acceptance rejects insecure HTTP" do
    previous = Rails.env
    begin
      Rails.env = "production"
      assert_no_difference "RiskAcceptance.count" do
        post finding_risk_acceptances_path(@finding), params: input, headers: headers
        assert_response :forbidden
      end
    ensure
      Rails.env = previous
    end
  end

  private

  def input
    { risk_acceptance: { reason: "Reviewed with compensating measures", expires_on: (Time.current.utc.to_date + 7).iso8601 } }
  end

  def headers
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(@settings.username, @settings.password) }
  end
end
