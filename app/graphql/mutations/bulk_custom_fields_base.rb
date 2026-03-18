module Mutations
  class BulkCustomFieldsBase < GraphQL::Schema::Mutation
    include BulkCustomFieldsSupport

    argument :input, Inputs::BulkCreateCustomFieldsInput, required: true

    type Types::BulkCreateCustomFieldsPayload, null: false

    def resolve(input:)
      if input.operations.present? && input.operations_url.present?
        raise GraphQL::ExecutionError, "Provide either operations or operationsUrl, not both"
      end

      # URL-based non-preview: enqueue a background job and return immediately
      if input.operations_url.present? && !input.preview
        return enqueue_url_job(input.operations_url, input.idempotency_key)
      end

      operations = if input.operations_url.present?
        # preview: true with URL — fetch synchronously so the caller gets immediate feedback
        load_operations_from_url(input.operations_url)
      else
        input.operations || []
      end

      if input.preview
        run_preview(operations)
      else
        if input.idempotency_key.present?
          existing = BulkOperation.find_by(idempotency_key: input.idempotency_key)
          return existing if existing
        end

        run_bulk_operation(operations, input.idempotency_key)
      end
    end

    private

    # Subclasses implement this to define create vs upsert behaviour
    def run_bulk_operation(operations, idempotency_key)
      raise NotImplementedError
    end

    # Subclasses declare which job class handles URL-based async processing
    def url_job_class
      raise NotImplementedError
    end

    def enqueue_url_job(url, idempotency_key)
      # Validate URL format before enqueueing so callers get an immediate error
      # rather than a silently-failed job.
      begin
        uri = URI.parse(url)
        raise GraphQL::ExecutionError, "operationsUrl must be an HTTP or HTTPS URL" unless uri.is_a?(URI::HTTP)
      rescue URI::InvalidURIError => e
        raise GraphQL::ExecutionError, "Invalid operationsUrl: #{e.message}"
      end

      if idempotency_key.present?
        existing = BulkOperation.find_by(idempotency_key: idempotency_key)
        return existing if existing
      end

      bulk_op = BulkOperation.create!(
        status:          :queued,
        total_rows:      0,
        processed_rows:  0,
        successful_rows: 0,
        failed_rows:     0,
        idempotency_key: idempotency_key
      )

      url_job_class.perform_later(bulk_op.id, url)
      bulk_op
    end

    # Wraps fetch_operations_from_url (from BulkCustomFieldsSupport) and converts
    # RuntimeError into GraphQL::ExecutionError for the preview sync path.
    def load_operations_from_url(url)
      fetch_operations_from_url(url)
    rescue RuntimeError => e
      raise GraphQL::ExecutionError, e.message
    end

    def track_bulk_operation(operations, idempotency_key)
      bulk_op = BulkOperation.create!(
        status:          :created,
        total_rows:      operations.size,
        processed_rows:  0,
        successful_rows: 0,
        failed_rows:     0,
        idempotency_key: idempotency_key,
        started_at:      Time.current
      )
      bulk_op.update!(status: :running)
      bulk_op
    end

    def finalise_bulk_operation(bulk_op, operations, successful, failed)
      bulk_op.update!(
        status:          operations.empty? || failed == 0 ? :completed : (failed == operations.size ? :failed : :partially_completed),
        processed_rows:  operations.size,
        successful_rows: successful,
        failed_rows:     failed,
        completed_at:    Time.current
      )
      bulk_op
    end

    def run_preview(operations)
      errors      = []
      valid_count = 0

      operations.each_with_index do |op, idx|
        row_errors = validate_operation(op, idx)
        if row_errors.any?
          errors.concat(row_errors)
        else
          valid_count += 1
        end
      end

      {
        total_rows:   operations.size,
        valid_rows:   valid_count,
        invalid_rows: errors.map { |e| e[:row_index] }.uniq.size,
        errors:       errors
      }
    end

    # Subclasses can override to change how the record is built for preview validation.
    # BulkUpsertCustomFields uses find_or_initialize_by so existing titles aren't flagged.
    def build_record_for_preview(op)
      CustomField.new(title: op.custom_field.title, body: op.custom_field.body)
    end

    def validate_operation(op, idx)
      errors = []

      cf = build_record_for_preview(op)
      unless cf.valid?
        cf.errors.each do |error|
          errors << { row_index: idx, sheet: nil, field: error.attribute.to_s, message: error.full_message }
        end
      end

      if op.validation_options
        vo = op.validation_options
        if vo.min_length && vo.max_length && vo.min_length > vo.max_length
          errors << { row_index: idx, sheet: nil, field: "min_length", message: "min_length cannot exceed max_length" }
        end
        if vo.pattern.present?
          begin
            Regexp.new(vo.pattern)
          rescue RegexpError
            errors << { row_index: idx, sheet: nil, field: "pattern", message: "Pattern is not a valid regular expression" }
          end
        end
      end

      errors
    end
  end
end
