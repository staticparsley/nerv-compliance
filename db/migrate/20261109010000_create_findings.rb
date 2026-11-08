class CreateFindings < ActiveRecord::Migration[8.1]
  def change
    create_table :findings do |t|
      t.references :integration, null: false, foreign_key: true
      t.references :control, null: false, foreign_key: true
      t.string :fingerprint, null: false
      t.string :namespace, null: false
      t.string :pod, null: false
      t.string :pod_uid
      t.string :container, null: false
      t.datetime :first_observed_at, null: false
      t.datetime :last_observed_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :findings, :fingerprint, unique: true
    add_index :findings, :resolved_at
    add_index :findings, :namespace

    create_table :finding_observations do |t|
      t.references :finding, null: false, foreign_key: true
      t.references :evidence, null: false, foreign_key: true, index: { unique: true }
      t.datetime :observed_at, null: false
      t.timestamps
    end

    create_table :risk_acceptances do |t|
      t.references :finding, null: false, foreign_key: true
      t.text :reason, null: false
      t.date :expires_on, null: false
      t.string :accepted_by, null: false
      t.datetime :accepted_at, null: false
      t.timestamps
    end
    add_reference :findings, :current_risk_acceptance, foreign_key: { to_table: :risk_acceptances }
  end
end
