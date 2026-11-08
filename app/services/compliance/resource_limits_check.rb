
module Compliance
  class ResourceLimitsCheck
    def initialize(pods:)
      @pods = pods
    end

    def call
      violations = []

      @pods.each do |pod|
        metadata = pod.fetch("metadata")
        spec = pod.fetch("spec")

        containers = [
          spec.fetch("containers", []),
          spec.fetch("initContainers", [])
        ].flatten

        containers.each do |container|
          limits = container.fetch("resources", {}).fetch("limits", {})

          missing = %w[cpu memory].reject do |resource|
            value = limits[resource]
            value && !value.to_s.empty?
          end

          next if missing.empty?

          violations << {
            namespace: metadata.fetch("namespace"),
            pod: metadata.fetch("name"),
            container: container.fetch("name"),
            missing_limits: missing,
            configured_limits: limits
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
