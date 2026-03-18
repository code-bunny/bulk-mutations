class DashboardController < ApplicationController
  def index
    @bulk_operations = BulkOperation.order(created_at: :desc)
    @custom_fields = CustomField.includes(:custom_field_validation_option).order(created_at: :desc)
  end
end
