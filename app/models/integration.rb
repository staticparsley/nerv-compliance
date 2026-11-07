class Integration < ApplicationRecord
  has_many :checks, dependent: :destroy
end
