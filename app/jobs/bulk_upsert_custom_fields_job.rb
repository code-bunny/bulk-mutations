class BulkUpsertCustomFieldsJob < BulkCustomFieldsJob
  private

  def process_operation(op)
    cf = CustomField.find_or_initialize_by(title: op.custom_field.title)
    cf.body = op.custom_field.body
    if cf.save
      cf.validation_options.destroy_all
      apply_validation_options(cf, op)
    end
    cf
  end
end
