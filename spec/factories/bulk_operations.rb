FactoryBot.define do
  factory :bulk_operation do
    status { :completed }
    total_rows { 3 }
    processed_rows { 3 }
    successful_rows { 3 }
    failed_rows { 0 }
    idempotency_key { nil }
    started_at { 1.minute.ago }
    completed_at { Time.current }
  end
end
