class Finding < ApplicationRecord
  belongs_to :integration
  belongs_to :control
  belongs_to :current_risk_acceptance, class_name: "RiskAcceptance", optional: true
  has_many :finding_observations, dependent: :restrict_with_exception
  has_many :evidences, through: :finding_observations
  has_many :risk_acceptances, dependent: :restrict_with_exception

  validates :fingerprint, :namespace, :pod, :container, :first_observed_at, :last_observed_at, presence: true

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :accepted_risks, ->(at = Time.current) {
    unresolved.joins(:current_risk_acceptance).where("risk_acceptances.expires_on > ?", at.utc.to_date)
  }
  scope :open_findings, ->(at = Time.current) {
    unresolved.left_joins(:current_risk_acceptance)
      .where("risk_acceptances.id IS NULL OR risk_acceptances.expires_on <= ?", at.utc.to_date)
  }

  # Status is calculated so expiry cannot depend on a scheduler or another scan.
  def status(at: Time.current)
    return "resolved" if resolved_at
    current_risk_acceptance&.active?(at: at) ? "accepted_risk" : "open"
  end

  def accept_risk!(reason:, expires_on:, accepted_by:)
    with_lock do
      acceptance = risk_acceptances.new(reason: reason, expires_on: expires_on,
                                       accepted_by: accepted_by, accepted_at: Time.current)
      if resolved_at
        acceptance.errors.add(:finding, "is resolved; only active violations can be accepted")
        raise ActiveRecord::RecordInvalid, acceptance
      end
      acceptance.save!
      update!(current_risk_acceptance: acceptance)
      acceptance
    end
  end
end
