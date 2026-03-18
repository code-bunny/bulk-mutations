module Types
  class BulkOperationType < Types::BaseObject
    field :id, ID, null: false
    field :status, Types::BulkOperationStatusEnum, null: false
    field :total_rows, Integer, null: true
    field :processed_rows, Integer, null: true
    field :successful_rows, Integer, null: true
    field :failed_rows, Integer, null: true
    field :result_url, String, null: true
    field :error_url, String, null: true
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :started_at, GraphQL::Types::ISO8601DateTime, null: true
    field :completed_at, GraphQL::Types::ISO8601DateTime, null: true
  end
end
