module Compliance
  class CheckRunner
    CONTROLS = [
      {
        key: "K8S-001",
        title: "No privileged containers",
        description: "Containers must not run in privileged mode",
        evaluator: PrivilegedContainersCheck
      },
      {
        key: "K8S-002",
        title: "Enforce non-root execution",
        description: "Containers must explicitly require non-root execution",
        evaluator: NonRootCheck
      },
      {
        key: "K8S-003",
        title: "Container resource limits",
        description: "Containers must define CPU and memory limits",
        evaluator: ResourceLimitsCheck
      }
    ].freeze

    def call
      integration = Integration.find_or_create_by!(
        name: "NERV Kubernetes",
        provider: "kubernetes"
      )

      # One API call, shared across both evaluations.
      pods = Kubernetes::PodClient.new.list_pods

      CONTROLS.map do |definition|
        control = Control.find_or_create_by!(key: definition[:key]) do |record|
          record.title = definition[:title]
          record.description = definition[:description]
        end

        result = definition[:evaluator].new(pods: pods).call

        Check.transaction do
          check = Check.create!(
            control: control,
            integration: integration,
            status: result[:status],
            checked_at: Time.current,
            details: "#{result[:pods_scanned]} pods scanned, " \
                     "#{result[:violations].length} findings"
          )

          check.evidences.create!(
            resource: "cluster/pods",
            payload: {
              control: definition[:key],
              pods_scanned: result[:pods_scanned],
              findings: result[:violations].length,
              evaluated_at: check.checked_at.iso8601
            }
          )

          result[:violations].each do |violation|
            check.evidences.create!(
              resource: "#{violation[:namespace]}/#{violation[:pod]}",
              payload: violation
            )
          end

          check
        end
      end
    end
  end
end
