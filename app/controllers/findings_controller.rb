class FindingsController < ApplicationController
  def index
    @status = %w[open accepted_risk resolved all].include?(params[:status]) ? params[:status] : "open"
    findings = case @status
    when "open" then Finding.open_findings
    when "accepted_risk" then Finding.accepted_risks
    when "resolved" then Finding.resolved
    else Finding.all
    end
    findings = findings.where(control_id: params[:control_id]) if params[:control_id].present?
    findings = findings.where(namespace: params[:namespace]) if params[:namespace].present?
    @page = [ params[:page].to_i, 1 ].max
    records = findings.includes(:control, :current_risk_acceptance)
      .order(last_observed_at: :desc, id: :desc).offset((@page - 1) * 20).limit(21).to_a
    @more = records.length > 20
    @findings = records.first(20)
    @controls = Control.order(:key)
  end

  def show
    @finding = Finding.includes(:control, :current_risk_acceptance).find(params[:id])
    @observations = @finding.finding_observations.includes(evidence: :check).order(observed_at: :desc).limit(50)
    @acceptances = @finding.risk_acceptances.order(accepted_at: :desc, id: :desc)
  end
end
