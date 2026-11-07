
module Compliance
  class PrivilegedContainersCheck
    def initialize(pods:)
      @pods = pods
    end

    def call
      violations = []

      @pods.each do |pod|
        metadata = pod.fetch("metadata")
        spec = pod.fetch("spec")

        namespace = metadata.fetch("namespace")
        pod_name = metadata.fetch("name")

        container_groups = [
          spec.fetch("containers", []),
          spec.fetch("initContainers", []),
          spec.fetch("ephemeralContainers", [])
        ]

        container_groups.flatten.each do |container|
          next unless container.dig("securityContext", "privileged") == true

          violations << {
            namespace: namespace,
            pod: pod_name,
            container: container.fetch("name"),
            privileged: true
          }
        end
      end

      {
        status: violations.empty? ? "pass" : "fail",
        pods_scanned: @pods.length,
        violations: violations
      }
    end
  end
end

