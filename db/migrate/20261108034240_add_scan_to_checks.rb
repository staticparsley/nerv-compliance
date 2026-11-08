class AddScanToChecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :checks, :scan, null: true, foreign_key: true
  end
end
