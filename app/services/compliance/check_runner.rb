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

    def initialize(pod_client: nil)
      @pod_client = pod_client
    end

    # Returns the execution; compliance outcomes live on scan.checks.
    def call
      integration = Integration.find_or_create_by!(
        name: "NERV Kubernetes",
        provider: "kubernetes"
      )
      scan = integration.scans.create!(status: "running", started_at: Time.current)
      errors = []

      begin
        pods = (@pod_client || Kubernetes::PodClient.new).list_pods
        raise TypeError, "Expected a pod list" unless pods.is_a?(Array)
      rescue StandardError => error
        acquisition_error = error
      end

      CONTROLS.each do |definition|
        control = Control.find_or_create_by!(key: definition[:key]) do |record|
          record.title = definition[:title]
          record.description = definition[:description]
        end

        begin
          raise acquisition_error if acquisition_error
          result = definition[:evaluator].new(pods: pods).call
          persist_result(scan, control, result)
        rescue StandardError => error
          # Roll back incomplete evidence before recording an unknown outcome.
          message = "#{definition[:key]}: #{error.class}"
          errors << message
          Check.create!(
            scan: scan, control: control, integration: integration, status: "error",
            checked_at: Time.current, details: "Evaluation unavailable (#{error.class})"
          )
        end
      end

      scan.update!(
        status: errors.empty? ? "completed" : "error",
        completed_at: Time.current,
        error_message: errors.presence&.join("; ")
      )
      scan
    rescue StandardError => error
      # Persistence failures must remain visible to the caller.
      scan&.update!(status: "error", completed_at: Time.current,
                    error_message: "Scan interrupted (#{error.class})")
      raise
    end

    private

    def persist_result(scan, control, result)
      Check.transaction(requires_new: true) do
        check = Check.create!(
          scan: scan, control: control,
          integration: scan.integration,
          status: result[:status],
          checked_at: Time.current,
          details: "#{result[:pods_scanned]} pods scanned, " \
                   "#{result[:violations].length} findings"
        )
        check.evidences.create!(
          resource: "cluster/pods",
          payload: {
            control: control.key,
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
      end
    end
  end
end
