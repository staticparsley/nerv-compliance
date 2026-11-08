class DashboardController < ApplicationController
  def index
      @latest_check = Check
        .includes(:control, :integration, :evidences)
        .order(checked_at: :desc)
        .first
  end
end
