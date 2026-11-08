module PodFixture
  def pod_fixture
    {
      "metadata" => { "namespace" => "test", "name" => "unit-01" },
      "spec" => {
        "containers" => [ { "name" => "app", "securityContext" => { "runAsNonRoot" => true },
                           "resources" => { "limits" => { "cpu" => "100m", "memory" => "64Mi" } } } ]
      }
    }
  end
end
