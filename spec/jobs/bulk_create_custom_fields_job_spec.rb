require "rails_helper"

RSpec.describe BulkCreateCustomFieldsJob do
  let(:operations_url) { "https://storage.example.com/uploads/custom_fields.json" }

  let(:valid_json) do
    [
      {
        "customField"       => { "title" => "Department", "body" => "Engineering" },
        "validationOptions" => { "required" => true, "maxLength" => 100 }
      },
      {
        "customField"       => { "title" => "Cost Centre", "body" => "CC-404" },
        "validationOptions" => { "pattern" => "^CC-\\d{3}$" }
      }
    ].to_json
  end

  let(:snake_case_json) do
    [
      {
        "custom_field"       => { "title" => "Region", "body" => "EMEA" },
        "validation_options" => { "required" => true, "max_length" => 50 }
      }
    ].to_json
  end

  let(:bulk_op) do
    BulkOperation.create!(
      status:          :queued,
      total_rows:      0,
      processed_rows:  0,
      successful_rows: 0,
      failed_rows:     0
    )
  end

  describe "#perform" do
    context "with a valid URL" do
      before do
        stub_request(:get, operations_url).to_return(
          status: 200,
          body: valid_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "creates the custom fields" do
        expect {
          described_class.perform_now(bulk_op.id, operations_url)
        }.to change { CustomField.count }.by(2)
      end

      it "marks the BulkOperation as COMPLETED" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.status).to eq("completed")
      end

      it "sets the row counts" do
        described_class.perform_now(bulk_op.id, operations_url)
        bulk_op.reload
        expect(bulk_op.total_rows).to eq(2)
        expect(bulk_op.successful_rows).to eq(2)
        expect(bulk_op.failed_rows).to eq(0)
      end

      it "persists validation options" do
        described_class.perform_now(bulk_op.id, operations_url)
        field = CustomField.find_by(title: "Department")
        expect(field.validation_options.first.required).to eq(true)
        expect(field.validation_options.first.max_length).to eq(100)
      end

      it "sets started_at and completed_at" do
        described_class.perform_now(bulk_op.id, operations_url)
        bulk_op.reload
        expect(bulk_op.started_at).to be_present
        expect(bulk_op.completed_at).to be_present
      end

      it "sets result_url pointing to the results report" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.result_url).to eq("/bulk_operations/#{bulk_op.id}/results")
      end

      it "leaves error_url nil when there are no failures" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.error_url).to be_nil
      end

      it "stores success details in results_data" do
        described_class.perform_now(bulk_op.id, operations_url)
        data = bulk_op.reload.results_data
        expect(data["successes"].map { |r| r["title"] }).to include("Department", "Cost Centre")
        expect(data["failures"]).to be_empty
      end
    end

    context "with snake_case JSON keys" do
      before do
        stub_request(:get, operations_url).to_return(
          status: 200,
          body: snake_case_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "accepts snake_case keys" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(CustomField.find_by(title: "Region")).to be_present
      end
    end

    context "when some rows fail to save" do
      before do
        CustomField.create!(title: "Department", body: "Existing")
        stub_request(:get, operations_url).to_return(
          status: 200, body: valid_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "marks the BulkOperation as PARTIALLY_COMPLETED" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.status).to eq("partially_completed")
      end

      it "records the correct counts" do
        described_class.perform_now(bulk_op.id, operations_url)
        bulk_op.reload
        expect(bulk_op.successful_rows).to eq(1)
        expect(bulk_op.failed_rows).to eq(1)
      end

      it "sets both result_url and error_url" do
        described_class.perform_now(bulk_op.id, operations_url)
        bulk_op.reload
        expect(bulk_op.result_url).to eq("/bulk_operations/#{bulk_op.id}/results")
        expect(bulk_op.error_url).to eq("/bulk_operations/#{bulk_op.id}/errors")
      end

      it "stores failure details including error messages in results_data" do
        described_class.perform_now(bulk_op.id, operations_url)
        failure = bulk_op.reload.results_data["failures"].first
        expect(failure["title"]).to eq("Department")
        expect(failure["errors"]).to include(match(/already been taken/i))
      end
    end

    context "when the URL returns a non-200 status" do
      before { stub_request(:get, operations_url).to_return(status: 404, body: "Not Found") }

      it "marks the BulkOperation as FAILED" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.status).to eq("failed")
      end

      it "does not create any custom fields" do
        expect {
          described_class.perform_now(bulk_op.id, operations_url)
        }.not_to change { CustomField.count }
      end
    end

    context "when the URL returns invalid JSON" do
      before { stub_request(:get, operations_url).to_return(status: 200, body: "not json") }

      it "marks the BulkOperation as FAILED" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.status).to eq("failed")
      end
    end

    context "when the URL returns a JSON object instead of an array" do
      before { stub_request(:get, operations_url).to_return(status: 200, body: '{"foo":"bar"}') }

      it "marks the BulkOperation as FAILED" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.status).to eq("failed")
      end
    end
  end
end
