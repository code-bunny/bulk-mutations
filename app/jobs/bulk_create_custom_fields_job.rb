class BulkCreateCustomFieldsJob < BulkCustomFieldsJob
  private

  def process_operation(op)
    cf = CustomField.new(title: op.custom_field.title, body: op.custom_field.body)
    if cf.save
      apply_validation_options(cf, op)
    end
    cf
  end
end
