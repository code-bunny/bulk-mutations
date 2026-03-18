class CreateCustomFields < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_fields do |t|
      t.string :title
      t.text :body

      t.timestamps
    end
  end
end
