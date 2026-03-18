class CreateBulkOperations < ActiveRecord::Migration[8.1]
  def change
    create_table :bulk_operations do |t|
      t.integer :status
      t.integer :total_rows
      t.integer :processed_rows
      t.integer :successful_rows
      t.integer :failed_rows
      t.string :result_url
      t.string :error_url
      t.string :idempotency_key
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
