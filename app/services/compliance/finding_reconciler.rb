module Compliance
  class FindingReconciler
    def initialize(check:, pods:)
      @check = check
      @pods = pods.index_by { |pod| [ pod.fetch("metadata").fetch("namespace"), pod.fetch("metadata").fetch("name") ] }
    end

    # Invoked inside the check/evidence transaction, only after successful evaluation.
    def call
      raise ArgumentError, "Cannot reconcile an unknown outcome" unless %w[pass fail].include?(@check.status)

      scope = Finding.where(integration: @check.integration, control: @check.control)
      observed_ids = []
      @check.evidences.where.not(resource: "cluster/pods").each do |evidence|
        payload = evidence.payload
        namespace, pod, container = payload.values_at("namespace", "pod", "container")
        uid = @pods.fetch([ namespace, pod ]).fetch("metadata")["uid"]
        fingerprint = Digest::SHA256.hexdigest(
          [ "v1", @check.integration_id, @check.control.key, namespace, pod, uid, container ].to_json
        )
        finding = scope.find_or_initialize_by(fingerprint: fingerprint)
        finding.assign_attributes(namespace: namespace, pod: pod, pod_uid: uid, container: container,
                                  first_observed_at: finding.first_observed_at || @check.checked_at,
                                  last_observed_at: @check.checked_at, resolved_at: nil)
        finding.save!
        finding.finding_observations.create!(evidence: evidence, observed_at: @check.checked_at)
        observed_ids << finding.id
      end

      scope.unresolved.where.not(id: observed_ids).find_each do |finding|
        finding.with_lock do
          finding.update!(resolved_at: @check.checked_at, current_risk_acceptance: nil)
        end
      end
    end
  end
end
