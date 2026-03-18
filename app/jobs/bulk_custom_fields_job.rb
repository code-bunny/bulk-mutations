class BulkCustomFieldsJob < ApplicationJob
  include BulkCustomFieldsSupport

  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(bulk_operation_id, url)
    bulk_op = BulkOperation.find(bulk_operation_id)
    bulk_op.update!(status: :running, started_at: Time.current)

    operations = fetch_operations_from_url(url)
    bulk_op.update!(total_rows: operations.size)

    successful = 0
    failed     = 0
    successes  = []
    failures   = []

    operations.each do |op|
      cf = process_operation(op)

      if cf.persisted?
        successful += 1
        successes << { title: cf.title, body: cf.body }
      else
        failed += 1
        failures << {
          title:  op.custom_field.title,
          body:   op.custom_field.body,
          errors: cf.errors.full_messages
        }
      end
    end

    status = if operations.empty? || failed == 0
      :completed
    elsif failed == operations.size
      :failed
    else
      :partially_completed
    end

    bulk_op.update!(
      status:          status,
      processed_rows:  operations.size,
      successful_rows: successful,
      failed_rows:     failed,
      completed_at:    Time.current,
      results_data:    { "successes" => successes, "failures" => failures },
      result_url:      (successful > 0 ? "/bulk_operations/#{bulk_op.id}/results" : nil),
      error_url:       (failed     > 0 ? "/bulk_operations/#{bulk_op.id}/errors"  : nil)
    )
  rescue RuntimeError => e
    bulk_op&.update!(status: :failed, completed_at: Time.current)
    logger.error "#{self.class}: #{e.message}"
  end

  private

  # Subclasses implement: return the CustomField instance.
  # If cf.persisted? it's a success; otherwise the errors explain why it failed.
  def process_operation(_op)
    raise NotImplementedError
  end
end
