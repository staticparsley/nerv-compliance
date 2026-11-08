require "net/http"
require "json"
require "uri"

module Kubernetes
  class PodClient
    def initialize
      @api_server = ENV.fetch("K8S_API_SERVER")
      @token = ENV.fetch("K8S_TOKEN")
      @ca_file = ENV.fetch("K8S_CA_FILE")
    end

    def list_pods
      uri = URI("#{@api_server.chomp('/')}/api/v1/pods")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ca_file = @ca_file
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = 5
      http.read_timeout = 15

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = "application/json"

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "Kubernetes API request failed: HTTP #{response.code}"
      end

      JSON.parse(response.body).fetch("items")
    end
  end
end
