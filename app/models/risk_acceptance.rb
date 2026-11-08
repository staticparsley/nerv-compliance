class RiskAcceptance < ApplicationRecord
  belongs_to :finding

  validates :reason, presence: true, length: { maximum: 5000 }
  validates :accepted_by, presence: true, length: { maximum: 255 }
  validates :accepted_at, :expires_on, presence: true
  validate :future_expiration, on: :create

  def active?(at: Time.current)
    expires_on > at.utc.to_date
  end

  # Renewals append a new decision; previous decisions remain auditable.
  def readonly?
    persisted? || super
  end

  private

  def future_expiration
    if expires_on && expires_on <= Time.current.utc.to_date
      errors.add(:expires_on, "must be a future date (expiry is at 00:00 UTC)")
    end
  end
end
