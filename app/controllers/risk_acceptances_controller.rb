class RiskAcceptancesController < ApplicationController
  include OperatorAuthorization
  before_action :authorize_operator

  def create
    finding = Finding.find(params[:finding_id])
    input = params.require(:risk_acceptance).permit(:reason, :expires_on)
    finding.accept_risk!(reason: input[:reason], expires_on: input[:expires_on], accepted_by: @operator_username)
    redirect_to finding_path(finding), notice: "Risk acceptance recorded. Raw compliance results are unchanged.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to finding_path(finding), alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end
end
