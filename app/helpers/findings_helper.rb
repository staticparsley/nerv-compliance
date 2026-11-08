module FindingsHelper
  def finding_status_class(finding)
    { "open" => "failed", "resolved" => "passed", "accepted_risk" => "accepted-risk" }.fetch(finding.status)
  end
end
