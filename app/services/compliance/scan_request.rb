module Compliance
  class ScanRequest
    def self.call
      Scan.transaction do
        scan, created = Scan.reserve
        if created
          job = ComplianceScanJob.perform_later(scan.id)
          raise ActiveJob::EnqueueError, "Assessment could not be queued" unless job
        end
        scan
      end
    end
  end
end
