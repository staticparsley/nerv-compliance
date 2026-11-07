
module Compliance
  class CheckRunner
    def call
      control = Control.find_or_create_by!(key: "K8S-001") do |record|
        record.title = "No privileged containers"
        record.description = "Containers must not run in privileged mode"
      end

      integration = Integration.find_or_create_by!(
        name: "NERV Kubernetes",
        provider: "kubernetes"
      )

      pods = Kubernetes::PodClient.new.list_pods

      result = PrivilegedContainersCheck.new(pods: pods).call

      Check.transaction do
        check = Check.create!(
          control: control,
          integration: integration,
          status: result[:status],
          checked_at: Time.current,
          details: "#{result[:pods_scanned]} pods scanned, " \
                   "#{result[:violations].length} violations"
        )

        check.evidences.create!(
          resource: "cluster/pods",
          payload: {
            control: "K8S-001",
            pods_scanned: result[:pods_scanned],
            violations_found: result[:violations].length,
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

