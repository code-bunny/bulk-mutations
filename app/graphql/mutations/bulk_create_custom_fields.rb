module Mutations
  class BulkCreateCustomFields < Mutations::BulkCustomFieldsBase
    type Types::BulkCreateCustomFieldsPayload, null: false

    private

    def url_job_class
      BulkCreateCustomFieldsJob
    end

    def run_bulk_operation(operations, idempotency_key)
      bulk_op = track_bulk_operation(operations, idempotency_key)
      successful = 0
      failed = 0

      operations.each do |op|
        cf = CustomField.new(title: op.custom_field.title, body: op.custom_field.body)
        if cf.save
          apply_validation_options(cf, op)
          successful += 1
        else
          failed += 1
        end
      end

      finalise_bulk_operation(bulk_op, operations, successful, failed)
    end
  end
end
