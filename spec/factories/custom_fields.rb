FactoryBot.define do
  factory :custom_field do
    sequence(:title) { |n| "Field #{n}" }
    body { "Some body text" }
  end
end
