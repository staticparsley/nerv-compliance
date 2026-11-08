require "test_helper"

class PodClientTest < ActiveSupport::TestCase
  test "incomplete pod lists are rejected and all Kubernetes requests remain read-only" do
    original_new = Net::HTTP.method(:new)
    keys = %w[K8S_API_SERVER K8S_TOKEN K8S_CA_FILE]
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    ENV["K8S_API_SERVER"] = "https://cluster.invalid"
    ENV["K8S_TOKEN"] = "synthetic-test-token"
    ENV["K8S_CA_FILE"] = "/tmp/test-ca.pem"
    request_received = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:body) { { "metadata" => { "continue" => "next-page" }, "items" => [] }.to_json }
    http = Struct.new(:use_ssl, :ca_file, :verify_mode, :open_timeout, :read_timeout).new
    http.define_singleton_method(:request) do |request|
      request_received = request
      response
    end
    Net::HTTP.define_singleton_method(:new) { |_host, _port| http }
    error = assert_raises(RuntimeError) { Kubernetes::PodClient.new.list_pods }
    assert_includes error.message, "Incomplete"
    assert_instance_of Net::HTTP::Get, request_received
    assert_equal "/api/v1/pods", request_received.path
    assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
    assert_equal true, http.use_ssl
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
