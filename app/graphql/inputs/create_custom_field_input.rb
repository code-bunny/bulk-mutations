module Inputs
  class CreateCustomFieldInput < Types::BaseInputObject
    graphql_name "CreateCustomFieldInput"
    argument :title, String, required: true
    argument :body, String, required: true
  end
end
