module Inputs
  class CustomFieldValidationOptionsInput < Types::BaseInputObject
    graphql_name "CustomFieldValidationOptionsInput"
    argument :required, Boolean, required: false, default_value: false
    argument :min_length, Integer, required: false
    argument :max_length, Integer, required: false
    argument :pattern, String, required: false
    argument :allowed_values, [String], required: false
  end
end
