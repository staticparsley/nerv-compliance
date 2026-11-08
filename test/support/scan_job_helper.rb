module ScanJobHelper
  def with_pod_client(pods: [], error: nil)
    original = Kubernetes::PodClient.method(:new)
    calls = []
    client = Object.new
    client.define_singleton_method(:list_pods) do
      calls << true
      raise error if error
      pods
    end
    Kubernetes::PodClient.define_singleton_method(:new) { client }
    yield calls
  ensure
    Kubernetes::PodClient.define_singleton_method(:new, original)
  end
end
