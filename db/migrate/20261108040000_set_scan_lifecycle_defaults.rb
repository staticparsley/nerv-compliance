class SetScanLifecycleDefaults < ActiveRecord::Migration[8.1]
  def change
    change_column_default :scans, :status, from: nil, to: "running"
  end
end
