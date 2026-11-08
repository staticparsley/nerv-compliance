class FindingObservation < ApplicationRecord
  belongs_to :finding
  belongs_to :evidence
  validates :observed_at, presence: true

  def readonly?
    persisted? || super
  end
end
