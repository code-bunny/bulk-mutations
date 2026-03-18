class CustomField < ApplicationRecord
  has_many :validation_options, class_name: "CustomFieldValidationOption", dependent: :destroy
  validates :title, presence: true, uniqueness: true
  validates :body, presence: true
end
