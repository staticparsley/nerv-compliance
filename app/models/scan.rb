class Scan < ApplicationRecord
  belongs_to :integration
  has_many :checks, dependent: :restrict_with_exception

  validates :status, inclusion: { in: %w[running completed error] }
  validates :started_at, presence: true
  validates :completed_at, presence: true, unless: -> { status == "running" }
  validates :error_message, presence: true, if: -> { status == "error" }
end
