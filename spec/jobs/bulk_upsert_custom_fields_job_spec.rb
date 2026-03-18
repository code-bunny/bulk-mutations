require "rails_helper"

RSpec.describe BulkUpsertCustomFieldsJob do
  let(:operations_url) { "https://storage.example.com/uploads/custom_fields.json" }

  let(:valid_json) do
    [
      {
        "customField"       => { "title" => "Department", "body" => "Engineering" },
        "validationOptions" => { "required" => true, "maxLength" => 100 }
      },
      {
        "customField" => { "title" => "Travel Tier", "body" => "Premium" },
        "validationOptions" => { "allowedValues" => ["Standard", "Premium"] }
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
    context "when records do not yet exist" do
      before do
        stub_request(:get, operations_url).to_return(
          status: 200, body: valid_json,
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
    end

    context "when records already exist" do
      before do
        cf = CustomField.create!(title: "Department", body: "Old body")
        cf.validation_options.create!(required: false, max_length: 50)

        stub_request(:get, operations_url).to_return(
          status: 200, body: valid_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "does not create a duplicate" do
        expect {
          described_class.perform_now(bulk_op.id, operations_url)
        }.to change { CustomField.count }.by(1) # only Travel Tier is new
      end

      it "updates the body of the existing record" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(CustomField.find_by(title: "Department").body).to eq("Engineering")
      end

      it "replaces the validation options" do
        described_class.perform_now(bulk_op.id, operations_url)
        field = CustomField.find_by(title: "Department")
        expect(field.validation_options.count).to eq(1)
        expect(field.validation_options.first.required).to eq(true)
        expect(field.validation_options.first.max_length).to eq(100)
      end
    end

    context "when the URL returns a non-200 status" do
      before { stub_request(:get, operations_url).to_return(status: 500, body: "Error") }

      it "marks the BulkOperation as FAILED" do
        described_class.perform_now(bulk_op.id, operations_url)
        expect(bulk_op.reload.status).to eq("failed")
      end
    end
  end
end
