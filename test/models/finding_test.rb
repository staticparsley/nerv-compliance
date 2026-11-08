require "test_helper"
require_relative "../support/finding_fixture"

class FindingTest < ActiveSupport::TestCase
  include FindingFixture

  test "accepted risks expire automatically at midnight UTC without a scan or job" do
    travel_to Time.utc(2026, 11, 9, 12) do
      finding = observed_finding
      acceptance = accept_finding(finding, expires_on: Date.new(2026, 11, 10))
      assert_equal "accepted_risk", finding.reload.status
      assert Finding.accepted_risks.exists?(finding.id)
      assert_not Finding.open_findings.exists?(finding.id)
      snapshot = acceptance.attributes
      travel 12.hours
      assert_equal "open", finding.status
      assert Finding.open_findings.exists?(finding.id)
      assert_not Finding.accepted_risks.exists?(finding.id)
      assert_equal snapshot, acceptance.reload.attributes
      assert_equal "fail", finding.evidences.sole.check.status
    end
  end

  test "recurring accepted violations remain failures and renewals append audit records" do
    finding = observed_finding
    first = accept_finding(finding)
    snapshots = finding.evidences.map(&:attributes)
    run_pods([ violating_pod ])
    assert_equal "accepted_risk", finding.reload.status
    assert_equal "fail", finding.evidences.order(:id).last.check.status
    second = accept_finding(finding, reason: "Reviewed renewal", expires_on: Time.current.utc.to_date + 2)
    assert_equal 2, finding.risk_acceptances.count
    assert_equal second, finding.reload.current_risk_acceptance
    assert_equal snapshots.first, Evidence.find(snapshots.first["id"]).attributes
    travel_to (Time.current.utc.to_date + 2).to_time(:utc) do
      assert_equal "open", finding.status
      assert first.active?
      assert_not Finding.accepted_risks.exists?(finding.id)
    end
  end

  test "reason actor and a valid future date are required" do
    finding = observed_finding
    [ { reason: "  " }, { expires_on: Date.yesterday }, { expires_on: Date.current },
      { expires_on: "not-a-date" }, { accepted_by: "" } ].each do |invalid|
      args = { reason: "Justification", expires_on: Time.current.utc.to_date + 2, accepted_by: "operator" }.merge(invalid)
      assert_no_difference "RiskAcceptance.count" do
        assert_raises(ActiveRecord::RecordInvalid) { finding.accept_risk!(**args) }
      end
    end
    assert_equal "open", finding.reload.status
  end

  test "resolved findings cannot be accepted" do
    finding = observed_finding
    run_pods([])
    assert_raises(ActiveRecord::RecordInvalid) { accept_finding(finding) }
    assert_equal "resolved", finding.reload.status
    assert_empty finding.risk_acceptances
  end

  test "checks evidence observations and risk decisions are immutable through Active Record" do
    finding = observed_finding
    acceptance = accept_finding(finding)
    evidence = finding.evidences.sole
    observation = finding.finding_observations.sole
    [ [ evidence.check, { status: "pass" } ], [ evidence, { payload: {} } ],
      [ observation, { observed_at: Time.current } ], [ acceptance, { reason: "Rewritten" } ] ].each do |record, changes|
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.update!(**changes) }
      assert_raises(ActiveRecord::ReadOnlyRecord) { record.destroy! }
    end
    assert_equal "fail", evidence.check.reload.status
    assert_equal "Compensating controls documented", acceptance.reload.reason
  end
end
