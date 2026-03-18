module Inputs
  class CreateCustomFieldWithValidationInput < Types::BaseInputObject
    graphql_name "CreateCustomFieldWithValidationInput"
    argument :custom_field, Inputs::CreateCustomFieldInput, required: true
    argument :validation_options, Inputs::CustomFieldValidationOptionsInput, required: false
  end
end
