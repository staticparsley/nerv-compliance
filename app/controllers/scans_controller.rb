class ScansController < ApplicationController
  include OperatorAuthorization

  before_action :authorize_operator, only: :create

  def index
    @page = [ params[:page].to_i, 1 ].max
    scans = Scan.recent.includes(:checks).offset((@page - 1) * 20).limit(21).to_a
    @more = scans.length > 20
    @scans = scans.first(20)
  end

  def show
    @scan = Scan.find(params[:id])
    @checks = @scan.checks.includes(:control, :evidences).order(:id)
  end

  def create
    scan = Compliance::ScanRequest.call
    redirect_to scan_path(scan), notice: "Assessment queued or already in progress.", status: :see_other
  rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError
    redirect_to scans_path, alert: "Assessment could not be queued. Please try again.", status: :see_other
  end
end
