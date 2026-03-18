# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :bulk_create_custom_fields, mutation: Mutations::BulkCreateCustomFields
    field :bulk_upsert_custom_fields, mutation: Mutations::BulkUpsertCustomFields
  end
end
