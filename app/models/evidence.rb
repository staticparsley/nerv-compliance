class Evidence < ApplicationRecord
  belongs_to :check

  def readonly?
    persisted? || super
  end
end
