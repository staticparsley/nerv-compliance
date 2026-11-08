class AddScanOperations < ActiveRecord::Migration[8.1]
  def change
    add_index :scans, "(1)", unique: true,
      where: "status IN ('queued', 'running')", name: "index_scans_one_active"
    add_index :scans, [ :created_at, :id ]
  end
end
