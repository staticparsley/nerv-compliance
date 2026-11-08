require "test_helper"
require_relative "../../support/pod_fixture"

class EvaluatorsTest < ActiveSupport::TestCase
  include PodFixture

  test "all controls pass compliant pods and empty clusters" do
    evaluators.each do |evaluator|
      result = evaluator.new(pods: [ pod_fixture ]).call
      assert_equal "pass", result[:status]
      assert_equal 1, result[:pods_scanned]
      assert_empty result[:violations]
      assert_equal "pass", evaluator.new(pods: []).call[:status]
    end
  end

  test "privileged containers includes regular init and ephemeral containers" do
    %w[containers initContainers ephemeralContainers].each do |group|
      pod = pod_fixture
      pod["spec"][group] = [ { "name" => "unsafe", "securityContext" => { "privileged" => true } } ]
      result = Compliance::PrivilegedContainersCheck.new(pods: [ pod ]).call
      assert_equal "fail", result[:status]
      assert_equal({ namespace: "test", pod: "unit-01", container: "unsafe", privileged: true }, result[:violations].sole)
    end
  end

  test "privileged false or absent passes" do
    [ false, nil ].each do |value|
      pod = pod_fixture
      pod["spec"]["containers"][0]["securityContext"]["privileged"] = value
      assert_equal "pass", Compliance::PrivilegedContainersCheck.new(pods: [ pod ]).call[:status]
    end
  end

  test "non-root inherits pod settings and container overrides for all groups" do
    %w[containers initContainers ephemeralContainers].each do |group|
      [ [ true, nil, "pass" ], [ true, false, "fail" ], [ false, true, "pass" ],
        [ nil, nil, "fail" ], [ nil, false, "fail" ] ].each do |pod_value, container_value, expected|
        pod = pod_fixture
        pod["spec"]["securityContext"] = { "runAsNonRoot" => pod_value }
        pod["spec"][group] = [ { "name" => "target", "securityContext" => { "runAsNonRoot" => container_value } } ]
        result = Compliance::NonRootCheck.new(pods: [ pod ]).call
        assert_equal expected, result[:status]
        if expected == "fail"
          assert_equal "target", result[:violations].sole[:container]
          assert_equal "test", result[:violations].sole[:namespace]
        end
      end
    end
  end

  test "resource limits requires both resources on regular and init containers" do
    %w[containers initContainers].each do |group|
      [ [ {}, %w[cpu memory] ], [ { "cpu" => "100m" }, [ "memory" ] ],
        [ { "memory" => "64Mi", "cpu" => "" }, [ "cpu" ] ] ].each do |limits, missing|
        pod = pod_fixture
        pod["spec"][group] = [ { "name" => "target", "resources" => { "limits" => limits } } ]
        result = Compliance::ResourceLimitsCheck.new(pods: [ pod ]).call
        assert_equal "fail", result[:status]
        assert_equal missing, result[:violations].sole[:missing_limits]
        assert_equal limits, result[:violations].sole[:configured_limits]
      end
    end
  end

  test "resource limits handles absent resources and excludes ephemeral containers" do
    pod = pod_fixture
    pod["spec"]["ephemeralContainers"] = [ { "name" => "debug" } ]
    assert_equal "pass", Compliance::ResourceLimitsCheck.new(pods: [ pod ]).call[:status]
    pod["spec"]["containers"][0].delete("resources")
    assert_equal %w[cpu memory], Compliance::ResourceLimitsCheck.new(pods: [ pod ]).call[:violations].sole[:missing_limits]
  end

  test "malformed pods raise instead of passing" do
    evaluators.each do |evaluator|
      assert_raises(KeyError) { evaluator.new(pods: [ {} ]).call }
    end
  end

  private

  def evaluators
    [ Compliance::PrivilegedContainersCheck, Compliance::NonRootCheck, Compliance::ResourceLimitsCheck ]
  end
end
