module OperatorAuthorization
  extend ActiveSupport::Concern

  private

  def authorize_operator
    settings = Rails.configuration.x.scan_operations
    return head :forbidden unless settings.username.present? && settings.password.present?
    return head :forbidden if Rails.env.production? && !request.ssl?

    authenticate_or_request_with_http_basic("NERV scan operator") do |username, password|
      # Compare both fields without leaking credential lengths.
      username_matches = ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(username), Digest::SHA256.hexdigest(settings.username)
      )
      password_matches = ActiveSupport::SecurityUtils.secure_compare(
        Digest::SHA256.hexdigest(password), Digest::SHA256.hexdigest(settings.password)
      )
      authorized = username_matches & password_matches
      @operator_username = username if authorized
      authorized
    end
  end
end
