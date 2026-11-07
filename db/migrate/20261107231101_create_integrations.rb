class CreateIntegrations < ActiveRecord::Migration[8.1]
  def change
    create_table :integrations do |t|
      t.string :name
      t.string :provider

      t.timestamps
    end
  end
end
