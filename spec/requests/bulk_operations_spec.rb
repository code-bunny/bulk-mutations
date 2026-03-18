require "rails_helper"

RSpec.describe "BulkOperation reports", type: :request do
  let(:bulk_op) do
    BulkOperation.create!(
      status:          :completed,
      total_rows:      3,
      processed_rows:  3,
      successful_rows: 2,
      failed_rows:     1,
      started_at:      1.minute.ago,
      completed_at:    Time.current,
      result_url:      nil,
      error_url:       nil,
      results_data:    {
        "successes" => [
          { "title" => "Department", "body" => "Engineering" },
          { "title" => "Travel Tier", "body" => "Premium" }
        ],
        "failures" => [
          { "title" => "", "body" => "foo", "errors" => ["Title can't be blank"] }
        ]
      }
    )
  end

  describe "GET /bulk_operations/:id/results" do
    it "returns 200" do
      get results_bulk_operation_path(bulk_op)
      expect(response).to have_http_status(:ok)
    end

    it "lists successful rows" do
      get results_bulk_operation_path(bulk_op)
      expect(response.body).to include("Department")
      expect(response.body).to include("Travel Tier")
    end

    it "does not show failed rows" do
      get results_bulk_operation_path(bulk_op)
      expect(response.body).not_to include("Title can&#39;t be blank")
    end
  end

  describe "GET /bulk_operations/:id/errors" do
    it "returns 200" do
      get errors_bulk_operation_path(bulk_op)
      expect(response).to have_http_status(:ok)
    end

    it "lists failed rows with their error messages" do
      get errors_bulk_operation_path(bulk_op)
      expect(response.body).to include("Title can&#39;t be blank")
    end

    it "does not show successful rows" do
      get errors_bulk_operation_path(bulk_op)
      expect(response.body).not_to include("Department")
    end
  end

  describe "with a non-existent bulk operation" do
    it "returns 404 for results" do
      get results_bulk_operation_path(id: 999999)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for errors" do
      get errors_bulk_operation_path(id: 999999)
      expect(response).to have_http_status(:not_found)
    end
  end
end
