class AddResultsDataToBulkOperations < ActiveRecord::Migration[8.0]
  def change
    add_column :bulk_operations, :results_data, :text
  end
end
