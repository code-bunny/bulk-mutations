class CustomField < ApplicationRecord
  has_one :custom_field_validation_option, dependent: :destroy
  validates :title, presence: true
  validates :body, presence: true
end
