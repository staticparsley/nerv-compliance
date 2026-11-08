class ComplianceScanJob < ApplicationJob
  # Scan and Solid Queue rows share a database/transaction. Do not defer enqueue.
  self.enqueue_after_transaction_commit = false

  def perform(scan_id)
    Compliance::CheckRunner.new.call(scan: Scan.find(scan_id))
  end
end
