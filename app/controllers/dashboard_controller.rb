class DashboardController < ApplicationController
  before_action :load_overview

  def index
    @latest_check = @recent_checks.first
  end

  def show
    @latest_check = Check
      .includes(:control, :integration, :evidences)
      .find(params[:id])

    render :index
  end

  private

  def load_overview
    @open_findings_count = Finding.open_findings.count
    @accepted_risks_count = Finding.accepted_risks.count
    @latest_scan = Scan.recent.first
    @active_scan = Scan.active.first
    @recent_checks = Check
      .includes(:control, :integration, :evidences)
      .order(checked_at: :desc, id: :desc)
      .limit(10)

    @latest_by_control = Check
      .includes(:control)
      .order(checked_at: :desc, id: :desc)
      .to_a
      .uniq(&:control_id)
  end
end
