module Types
  class BulkCreateCustomFieldsPayload < Types::BaseUnion
    description "Result of bulkCreateCustomFields — either a live job or a preview"
    possible_types Types::BulkOperationResultType, Types::BulkOperationPreviewResultType

    def self.resolve_type(object, _ctx)
      if object.is_a?(BulkOperation)
        Types::BulkOperationResultType
      else
        Types::BulkOperationPreviewResultType
      end
    end
  end
end
