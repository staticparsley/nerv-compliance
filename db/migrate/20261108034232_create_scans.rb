class CreateScans < ActiveRecord::Migration[8.1]
  def change
    create_table :scans do |t|
      t.references :integration, null: false, foreign_key: true
      t.string :status
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end
  end
end
