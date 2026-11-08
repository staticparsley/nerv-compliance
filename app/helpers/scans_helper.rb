module ScansHelper
  def scan_time(time)
    time&.utc&.strftime("%Y.%m.%d %H:%M:%S UTC") || "—"
  end

  def execution_class(scan)
    { "completed" => "passed", "error" => "execution-error" }.fetch(scan.status, "pending")
  end

  def manual_scans_enabled?
    settings = Rails.configuration.x.scan_operations
    settings.username.present? && settings.password.present? && (!Rails.env.production? || request.ssl?)
  end
end
