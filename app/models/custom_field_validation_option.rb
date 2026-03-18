class CustomFieldValidationOption < ApplicationRecord
  belongs_to :custom_field
  serialize :allowed_values, coder: JSON
end
