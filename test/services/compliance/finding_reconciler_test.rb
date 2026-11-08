require "test_helper"
require_relative "../../support/finding_fixture"

class FindingReconcilerTest < ActiveSupport::TestCase
  include FindingFixture

  test "violations recur under one identity with separate evidence for every scan" do
    travel_to Time.utc(2026, 11, 9, 12) do
      first = run_pods([ violating_pod ])
      assert_equal 3, Finding.count
      assert_equal 3, FindingObservation.count
      initial = Finding.order(:id).map { |finding| [ finding.id, finding.first_observed_at ] }.to_h
      snapshots = first.checks.includes(:evidences).map do |check|
        [ check.attributes, check.evidences.map(&:attributes) ]
      end
      travel 6.hours
      second = run_pods([ violating_pod ])
      assert_equal 3, Finding.count
      assert_equal 6, FindingObservation.count
      Finding.find_each do |finding|
        assert_equal initial[finding.id], finding.first_observed_at
        assert_equal Time.current, finding.last_observed_at
        assert_equal "open", finding.status
        assert_equal 2, finding.evidences.count
        assert_equal [ first.id, second.id ].sort, finding.evidences.map { |evidence| evidence.check.scan_id }.sort
      end
      assert_equal snapshots, first.checks.reload.includes(:evidences).map { |check| [ check.attributes, check.evidences.map(&:attributes) ] }
    end
  end

  test "changed violation details update the same finding and preserve past payloads" do
    pod = violating_pod
    run_pods([ pod ])
    finding = Finding.joins(:control).find_by!(controls: { key: "K8S-003" })
    initial_payload = finding.evidences.sole.payload.deep_dup
    pod["spec"]["containers"][0]["resources"] = { "limits" => { "cpu" => "100m" } }
    run_pods([ pod ])
    assert_equal 3, Finding.count
    assert_equal initial_payload, finding.evidences.order(:id).first.payload
    assert_equal [ "memory" ], finding.evidences.order(:id).last.payload["missing_limits"]
  end

  test "successful evaluations resolve absent violations and recurrence reopens the same finding" do
    finding = observed_finding
    accept_finding(finding)
    first_seen = finding.first_observed_at
    old_evidence = finding.evidences.sole.attributes
    run_pods([ pod_fixture ])
    finding.reload
    assert_equal "resolved", finding.status
    assert finding.resolved_at
    assert_nil finding.current_risk_acceptance_id
    assert_equal 1, finding.risk_acceptances.count
    run_pods([ violating_pod ])
    finding.reload
    assert_equal "open", finding.status
    assert_nil finding.resolved_at
    assert_equal first_seen, finding.first_observed_at
    assert_equal old_evidence, Evidence.find(old_evidence["id"]).attributes
  end

  test "a successful failing control resolves only findings absent from that snapshot" do
    pod1 = violating_pod
    pod2 = violating_pod(uid: "uid-02")
    pod2["metadata"]["name"] = "unit-02"
    run_pods([ pod1, pod2 ])
    run_pods([ pod2 ])
    assert_equal 3, Finding.open_findings.count
    assert_equal 3, Finding.resolved.count
    assert_equal [ "unit-02" ], Finding.open_findings.distinct.pluck(:pod)
    assert_equal %w[fail fail fail], Scan.recent.first.checks.pluck(:status)
  end

  test "API failures do not resolve any findings or extend last observed timestamps" do
    observed_finding
    before = Finding.order(:id).map(&:attributes)
    client = Object.new
    client.define_singleton_method(:list_pods) { raise IOError, "unavailable" }
    scan = Compliance::CheckRunner.new(pod_client: client).call
    assert_equal "error", scan.status
    assert_equal before, Finding.order(:id).map(&:attributes)
  end

  test "partial evaluation errors leave findings for the unknown control unchanged" do
    observed_finding
    limits = Finding.joins(:control).find_by!(controls: { key: "K8S-003" })
    before = limits.attributes
    pod = pod_fixture
    pod["spec"]["containers"][0]["resources"] = false
    scan = run_pods([ pod ])
    assert_equal "error", scan.status
    assert_equal before, limits.reload.attributes
    assert_equal 2, Finding.resolved.count
    assert_equal 1, Finding.open_findings.count
  end

  test "system namespaces are open by default and UID replacements do not inherit acceptance" do
    run_pods([ violating_pod(namespace: "kube-system") ])
    assert_equal 3, Finding.open_findings.where(namespace: "kube-system").count
    original = Finding.joins(:control).find_by!(controls: { key: "K8S-001" })
    accept_finding(original)
    run_pods([ violating_pod(namespace: "kube-system", uid: "replacement") ])
    assert_equal "resolved", original.reload.status
    replacement = Finding.open_findings.joins(:control).find_by!(controls: { key: "K8S-001" })
    assert_not_equal original.id, replacement.id
    assert_nil replacement.current_risk_acceptance_id
  end

  test "identity distinguishes namespaces and containers and supports pods without UID" do
    pod = violating_pod(namespace: "other", uid: nil)
    pod["spec"]["initContainers"] = [ { "name" => "init", "securityContext" => { "privileged" => true } } ]
    run_pods([ violating_pod(uid: nil), pod ])
    assert_equal 9, Finding.count
    run_pods([ violating_pod(uid: nil), pod ])
    assert_equal 9, Finding.count
    assert_equal 18, FindingObservation.count
  end

  test "identical resources in another integration have separate findings and resolution scope" do
    original = observed_finding
    other = Integration.create!(name: "Other cluster", provider: "kubernetes")
    scan = Scan.create!(integration: other, status: "completed", started_at: Time.current, completed_at: Time.current)
    check = Check.create!(scan: scan, integration: other, control: original.control,
                          status: "fail", checked_at: Time.current)
    source = original.evidences.sole
    check.evidences.create!(resource: source.resource, payload: source.payload)
    Finding.transaction do
      Compliance::FindingReconciler.new(check: check, pods: [ violating_pod ]).call
    end
    separate = Finding.find_by!(integration: other)
    assert_not_equal original.fingerprint, separate.fingerprint
    run_pods([])
    assert_equal "resolved", original.reload.status
    assert_equal "open", separate.reload.status
    assert_equal 1, separate.evidences.count
  end

  test "finding persistence failures roll back reconciliation and evidence" do
    callback = -> { raise ActiveRecord::RecordInvalid, self }
    Finding.set_callback(:create, :before, callback)
    begin
      scan = run_pods([ violating_pod ])
      assert_equal "error", scan.status
      assert_equal %w[error error error], scan.checks.pluck(:status)
      assert_equal 0, Finding.count
      assert_equal 0, FindingObservation.count
      assert_equal 0, Evidence.count
    ensure
      Finding.skip_callback(:create, :before, callback)
    end
  end
end
