require "test_helper"

class ScanTest < ActiveSupport::TestCase
  test "validates lifecycle fields" do
    integration = Integration.create!(name: "test", provider: "kubernetes")
    scan = integration.scans.new(started_at: Time.current)
    assert scan.valid?
    scan.status = "unknown"
    assert_not scan.valid?
    scan.status = "completed"
    assert_not scan.valid?
    scan.completed_at = Time.current
    assert scan.valid?
    scan.status = "error"
    assert_not scan.valid?
    scan.error_message = "Evaluation unavailable"
    assert scan.valid?
    scan.started_at = nil
    assert_not scan.valid?
  end

  test "scan deletion cannot delete historical checks or evidence" do
    integration = Integration.create!(name: "test", provider: "kubernetes")
    scan = integration.scans.create!(started_at: Time.current)
    check = scan.checks.create!(integration: integration, control: Control.create!(key: "test"), status: "pass")
    evidence = check.evidences.create!(resource: "test", payload: {})
    assert_raises(ActiveRecord::DeleteRestrictionError) { scan.destroy! }
    assert Check.exists?(check.id)
    assert Evidence.exists?(evidence.id)
  end
end
