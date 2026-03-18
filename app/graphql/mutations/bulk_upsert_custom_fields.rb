module Mutations
  class BulkUpsertCustomFields < Mutations::BulkCustomFieldsBase
    type Types::BulkCreateCustomFieldsPayload, null: false

    private

    def url_job_class
      BulkUpsertCustomFieldsJob
    end

    def build_record_for_preview(op)
      cf = CustomField.find_or_initialize_by(title: op.custom_field.title)
      cf.body = op.custom_field.body
      cf
    end

    def run_bulk_operation(operations, idempotency_key)
      bulk_op   = track_bulk_operation(operations, idempotency_key)
      successful = 0
      failed     = 0
      successes  = []
      failures   = []

      operations.each do |op|
        cf = CustomField.find_or_initialize_by(title: op.custom_field.title)
        cf.body = op.custom_field.body

        if cf.save
          cf.validation_options.destroy_all
          apply_validation_options(cf, op)
          successful += 1
          successes << { "title" => cf.title, "body" => cf.body }
        else
          failed += 1
          failures << { "title" => op.custom_field.title, "body" => op.custom_field.body, "errors" => cf.errors.full_messages }
        end
      end

      finalise_bulk_operation(bulk_op, operations, successful, failed, successes: successes, failures: failures)
    end
  end
end
