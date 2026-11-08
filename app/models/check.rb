class Check < ApplicationRecord
  belongs_to :scan, optional: true # Historical checks predate scan tracking.
  belongs_to :control
  belongs_to :integration

  has_many :evidences, dependent: :destroy

  validates :status, inclusion: {
    in: %w[pass fail error]
  }
end
