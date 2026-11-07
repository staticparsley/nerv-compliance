class Check < ApplicationRecord
  belongs_to :control
  belongs_to :integration

  has_many :evidences, dependent: :destroy

  validates :status, inclusion: {
    in: %w[pass fail error]
  }
end
