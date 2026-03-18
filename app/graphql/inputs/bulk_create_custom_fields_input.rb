module Inputs
  class BulkCreateCustomFieldsInput < Types::BaseInputObject
    argument :operations, [Inputs::CreateCustomFieldWithValidationInput], required: false
    argument :operations_url, String, required: false
    argument :preview, Boolean, required: false, default_value: false
    argument :idempotency_key, String, required: false
  end
end
