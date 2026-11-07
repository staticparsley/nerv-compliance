class CreateControls < ActiveRecord::Migration[8.1]
  def change
    create_table :controls do |t|
      t.string :key
      t.string :title
      t.text :description

      t.timestamps
    end
  end
end
