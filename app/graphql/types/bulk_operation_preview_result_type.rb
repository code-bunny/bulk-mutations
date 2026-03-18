module Types
  class BulkOperationPreviewResultType < Types::BaseObject
    field :total_rows, Integer, null: false
    field :valid_rows, Integer, null: false
    field :invalid_rows, Integer, null: false
    field :errors, [Types::RowErrorType], null: false
  end
end
