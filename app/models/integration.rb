class Integration < ApplicationRecord
  has_many :scans, dependent: :restrict_with_exception
  has_many :checks, dependent: :destroy
end
