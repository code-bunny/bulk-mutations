class CreateCustomFieldValidationOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_field_validation_options do |t|
      t.references :custom_field, null: false, foreign_key: true
      t.boolean :required
      t.integer :min_length
      t.integer :max_length
      t.string :pattern
      t.text :allowed_values

      t.timestamps
    end
  end
end
