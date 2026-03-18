class DashboardController < ApplicationController
  PER_PAGE = 15

  def index
    @tab = params[:tab].presence_in(%w[operations fields]) || "operations"

    @pagy_operations, @bulk_operations = pagy(
      BulkOperation.order(created_at: :desc),
      limit: PER_PAGE
    )

    @pagy_fields, @custom_fields = pagy(
      CustomField.includes(:custom_field_validation_option).order(created_at: :desc),
      limit: PER_PAGE
    )
  end

  def reset
    BulkOperation.delete_all
    redirect_to root_path(tab: "operations"), status: :see_other
  end

  def reset_fields
    CustomField.destroy_all
    redirect_to root_path(tab: "fields"), status: :see_other
  end
end
