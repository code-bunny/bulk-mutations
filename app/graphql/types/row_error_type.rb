module Types
  class RowErrorType < Types::BaseObject
    field :row_index, Integer, null: false
    field :sheet, String, null: true
    field :field, String, null: true
    field :message, String, null: false
  end
end
