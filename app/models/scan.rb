class Scan < ApplicationRecord
  ACTIVE_STATUSES = %w[queued running].freeze

  belongs_to :integration
  has_many :checks, dependent: :restrict_with_exception

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  validates :status, inclusion: { in: %w[queued running completed error] }
  validates :started_at, presence: true, unless: -> { status == "queued" }
  validates :completed_at, presence: true, if: -> { %w[completed error].include?(status) }
  validates :error_message, presence: true, if: -> { status == "error" }

  # Serialize reservations across web processes, scheduled jobs, and CLI scans.
  # The partial unique index is a second guard, including callers outside this method.
  def self.reserve(status: "queued")
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(841001)")
      existing = active.first
      next [ existing, false ] if existing

      integration = Integration.find_or_create_by!(name: "NERV Kubernetes", provider: "kubernetes")
      scan = create!(integration: integration, status: status,
                     started_at: status == "running" ? Time.current : nil)
      [ scan, true ]
    end
  end

  def execution_label
    status == "error" ? "FAILED" : status.upcase
  end
end
