require "net/http"
require "json"

module Mutations
  class BulkCreateCustomFields < GraphQL::Schema::Mutation
    # Lightweight structs used to normalise URL-fetched rows into the same
    # interface as graphql-ruby input objects (.custom_field.title, etc.)
    CustomFieldData      = Data.define(:title, :body)
    ValidationOptionsData = Data.define(:required, :min_length, :max_length, :pattern, :allowed_values)
    OperationData        = Data.define(:custom_field, :validation_options)

    argument :input, Inputs::BulkCreateCustomFieldsInput, required: true

    type Types::BulkCreateCustomFieldsPayload, null: false

    def resolve(input:)
      if input.operations.present? && input.operations_url.present?
        raise GraphQL::ExecutionError, "Provide either operations or operationsUrl, not both"
      end

      operations = if input.operations_url.present?
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

        run_bulk_create(operations, input.idempotency_key)
      end
    end

    private

    def load_operations_from_url(url)
      uri = URI.parse(url)
      raise GraphQL::ExecutionError, "operationsUrl must be an HTTP or HTTPS URL" unless uri.is_a?(URI::HTTP)

      response = Net::HTTP.get_response(uri)
      unless response.is_a?(Net::HTTPSuccess)
        raise GraphQL::ExecutionError, "Failed to fetch operationsUrl (HTTP #{response.code})"
      end

      rows = JSON.parse(response.body)
      raise GraphQL::ExecutionError, "operationsUrl must return a JSON array" unless rows.is_a?(Array)

      rows.map do |row|
        cf_data   = row["customField"] || row["custom_field"] || {}
        vo_data   = row["validationOptions"] || row["validation_options"]

        custom_field = CustomFieldData.new(
          title: cf_data["title"].to_s,
          body:  cf_data["body"].to_s
        )

        validation_options = if vo_data
          ValidationOptionsData.new(
            required:       vo_data["required"] || false,
            min_length:     vo_data["minLength"]      || vo_data["min_length"],
            max_length:     vo_data["maxLength"]      || vo_data["max_length"],
            pattern:        vo_data["pattern"],
            allowed_values: vo_data["allowedValues"]  || vo_data["allowed_values"]
          )
        end

        OperationData.new(custom_field: custom_field, validation_options: validation_options)
      end
    rescue URI::InvalidURIError => e
      raise GraphQL::ExecutionError, "Invalid operationsUrl: #{e.message}"
    rescue JSON::ParserError => e
      raise GraphQL::ExecutionError, "operationsUrl did not return valid JSON: #{e.message}"
    end

    def run_preview(operations)
      errors = []
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
        total_rows: operations.size,
        valid_rows: valid_count,
        invalid_rows: errors.map { |e| e[:row_index] }.uniq.size,
        errors: errors
      }
    end

    def run_bulk_create(operations, idempotency_key)
      bulk_op = BulkOperation.create!(
        status: :created,
        total_rows: operations.size,
        processed_rows: 0,
        successful_rows: 0,
        failed_rows: 0,
        idempotency_key: idempotency_key,
        started_at: Time.current
      )

      bulk_op.update!(status: :running)

      successful = 0
      failed = 0

      operations.each do |op|
        cf = CustomField.new(title: op.custom_field.title, body: op.custom_field.body)
        if cf.save
          if op.validation_options
            vo = op.validation_options
            cf.create_custom_field_validation_option(
              required:       vo.required,
              min_length:     vo.min_length,
              max_length:     vo.max_length,
              pattern:        vo.pattern,
              allowed_values: vo.allowed_values
            )
          end
          successful += 1
        else
          failed += 1
        end
      end

      bulk_op.update!(
        status: operations.empty? || failed == 0 ? :completed : (failed == operations.size ? :failed : :partially_completed),
        processed_rows: operations.size,
        successful_rows: successful,
        failed_rows: failed,
        completed_at: Time.current
      )

      bulk_op
    end

    def validate_operation(op, idx)
      errors = []
      cf = op.custom_field

      if cf.title.blank?
        errors << { row_index: idx, sheet: nil, field: "title", message: "Title can't be blank" }
      end
      if cf.body.blank?
        errors << { row_index: idx, sheet: nil, field: "body", message: "Body can't be blank" }
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
