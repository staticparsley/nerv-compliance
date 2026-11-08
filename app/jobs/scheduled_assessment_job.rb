class ScheduledAssessmentJob < ApplicationJob
  def perform
    Compliance::ScanRequest.call
  end
end
