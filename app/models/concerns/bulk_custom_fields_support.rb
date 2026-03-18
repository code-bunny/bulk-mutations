require "net/http"
require "json"

# Shared between Mutations::BulkCustomFieldsBase and the bulk jobs.
# Provides Data structs, URL fetching (raises plain RuntimeError), and
# validation option persistence.
module BulkCustomFieldsSupport
  extend ActiveSupport::Concern

  CustomFieldData       = Data.define(:title, :body)
  ValidationOptionsData = Data.define(:required, :min_length, :max_length, :pattern, :allowed_values)
  OperationData         = Data.define(:custom_field, :validation_options)

  # Fetches and parses a JSON array from the given URL.
  # Raises RuntimeError (not GraphQL::ExecutionError) so callers in jobs and
  # mutations can handle errors in their own way.
  def fetch_operations_from_url(url)
    uri = URI.parse(url)
    raise "operationsUrl must be an HTTP or HTTPS URL" unless uri.is_a?(URI::HTTP)

    response = Net::HTTP.get_response(uri)
    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to fetch operationsUrl (HTTP #{response.code})"
    end

    rows = JSON.parse(response.body)
    raise "operationsUrl must return a JSON array" unless rows.is_a?(Array)

    rows.map do |row|
      cf_data = row["customField"] || row["custom_field"] || {}
      vo_data = row["validationOptions"] || row["validation_options"]

      custom_field = CustomFieldData.new(
        title: cf_data["title"].to_s,
        body:  cf_data["body"].to_s
      )

      validation_options = if vo_data
        ValidationOptionsData.new(
          required:       vo_data["required"] || false,
          min_length:     vo_data["minLength"]     || vo_data["min_length"],
          max_length:     vo_data["maxLength"]     || vo_data["max_length"],
          pattern:        vo_data["pattern"],
          allowed_values: vo_data["allowedValues"] || vo_data["allowed_values"]
        )
      end

      OperationData.new(custom_field: custom_field, validation_options: validation_options)
    end
  rescue URI::InvalidURIError => e
    raise "Invalid operationsUrl: #{e.message}"
  rescue JSON::ParserError => e
    raise "operationsUrl did not return valid JSON: #{e.message}"
  end

  def apply_validation_options(cf, op)
    return unless op.validation_options

    vo = op.validation_options
    cf.validation_options.create!(
      required:       vo.required,
      min_length:     vo.min_length,
      max_length:     vo.max_length,
      pattern:        vo.pattern,
      allowed_values: vo.allowed_values
    )
  end
end
