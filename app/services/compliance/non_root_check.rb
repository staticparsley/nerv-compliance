
module Compliance
  class NonRootCheck
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

        pod_non_root = spec.dig("securityContext", "runAsNonRoot")

        containers = [
          spec.fetch("containers", []),
          spec.fetch("initContainers", []),
          spec.fetch("ephemeralContainers", [])
        ].flatten

        containers.each do |container|
          container_non_root = container.dig(
            "securityContext", "runAsNonRoot"
          )

          effective_non_root =
            container_non_root.nil? ? pod_non_root : container_non_root

          next if effective_non_root == true

          violations << {
            namespace: namespace,
            pod: pod_name,
            container: container.fetch("name"),
            run_as_non_root: effective_non_root,
            reason: effective_non_root == false ?
              "Explicitly allows root execution" :
              "Non-root execution is not enforced"
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
