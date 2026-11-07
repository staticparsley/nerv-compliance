class CreateChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :checks do |t|
      t.references :control, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: true
      t.string :status
      t.datetime :checked_at
      t.text :details

      t.timestamps
    end
  end
end
