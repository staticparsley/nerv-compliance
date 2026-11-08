require_relative "pod_fixture"

module FindingFixture
  include PodFixture

  def violating_pod(namespace: "test", uid: "uid-01")
    pod = pod_fixture
    pod["metadata"].merge!("namespace" => namespace, "uid" => uid)
    container = pod["spec"]["containers"][0]
    container["securityContext"] = { "privileged" => true }
    container.delete("resources")
    pod
  end

  def run_pods(pods)
    client = Object.new
    client.define_singleton_method(:list_pods) { pods }
    Compliance::CheckRunner.new(pod_client: client).call
  end

  def observed_finding
    run_pods([ violating_pod ])
    Finding.joins(:control).find_by!(controls: { key: "K8S-001" })
  end

  def accept_finding(finding, reason: "Compensating controls documented", expires_on: Time.current.utc.to_date + 7)
    finding.accept_risk!(reason: reason, expires_on: expires_on, accepted_by: "operator")
  end
end
