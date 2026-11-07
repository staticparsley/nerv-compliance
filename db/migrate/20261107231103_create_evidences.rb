class CreateEvidences < ActiveRecord::Migration[8.1]
  def change
    create_table :evidences do |t|
      t.references :check, null: false, foreign_key: true
      t.string :resource
      t.jsonb :payload

      t.timestamps
    end
  end
end
