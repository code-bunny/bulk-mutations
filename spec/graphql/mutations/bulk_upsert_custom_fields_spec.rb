require "rails_helper"

RSpec.describe "bulkUpsertCustomFields mutation" do
  let(:schema) { BulkrailsSchema }

  let(:mutation_string) do
    <<~GQL
      mutation BulkUpsertCustomFields($input: BulkCreateCustomFieldsInput!) {
        bulkUpsertCustomFields(input: $input) {
          ... on BulkOperationResult {
            id
            status
            totalRows
            successfulRows
            failedRows
          }
          ... on BulkOperationPreviewResult {
            totalRows
            validRows
            invalidRows
            errors {
              rowIndex
              field
              message
            }
          }
        }
      }
    GQL
  end

  def execute(variables = {})
    schema.execute(mutation_string, variables: variables, context: {})
  end

  let(:operations) do
    [
      {
        "customField" => { "title" => "Department", "body" => "Engineering" },
        "validationOptions" => { "required" => true, "maxLength" => 100 }
      },
      {
        "customField" => { "title" => "Travel Tier", "body" => "Premium" },
        "validationOptions" => { "allowedValues" => [ "Standard", "Premium", "Executive" ] }
      }
    ]
  end

  describe "create behaviour (no existing record)" do
    it "creates new custom fields" do
      expect {
        execute("input" => { "preview" => false, "operations" => operations })
      }.to change { CustomField.count }.by(2)
    end

    it "returns a completed BulkOperationResult" do
      result = execute("input" => { "preview" => false, "operations" => operations })
      data = result.dig("data", "bulkUpsertCustomFields")

      expect(data["status"]).to eq("COMPLETED")
      expect(data["successfulRows"]).to eq(2)
      expect(data["failedRows"]).to eq(0)
    end

    it "persists validation options" do
      execute("input" => { "preview" => false, "operations" => operations })
      field = CustomField.find_by(title: "Department")

      expect(field.validation_options.first.required).to eq(true)
      expect(field.validation_options.first.max_length).to eq(100)
    end

    it "sets result_url even when all rows succeed" do
      execute("input" => { "preview" => false, "operations" => operations })
      bulk_op = BulkOperation.last
      expect(bulk_op.result_url).to eq("/bulk_operations/#{bulk_op.id}/results")
    end

    it "leaves error_url nil when all rows succeed" do
      execute("input" => { "preview" => false, "operations" => operations })
      expect(BulkOperation.last.error_url).to be_nil
    end

    it "stores success titles in results_data" do
      execute("input" => { "preview" => false, "operations" => operations })
      titles = BulkOperation.last.results_data["successes"].map { |r| r["title"] }
      expect(titles).to include("Department", "Travel Tier")
    end
  end

  describe "update behaviour (existing record)" do
    before do
      cf = CustomField.create!(title: "Department", body: "Old body")
      cf.validation_options.create!(required: false, max_length: 50)
    end

    it "does not create a duplicate" do
      expect {
        execute("input" => { "preview" => false, "operations" => operations })
      }.to change { CustomField.count }.by(1) # only Travel Tier is new
    end

    it "updates the body of the existing record" do
      execute("input" => { "preview" => false, "operations" => operations })
      expect(CustomField.find_by(title: "Department").body).to eq("Engineering")
    end

    it "replaces the validation options" do
      execute("input" => { "preview" => false, "operations" => operations })
      field = CustomField.find_by(title: "Department")

      expect(field.validation_options.count).to eq(1)
      expect(field.validation_options.first.required).to eq(true)
      expect(field.validation_options.first.max_length).to eq(100)
    end

    it "removes old validation options when none are provided" do
      ops = [ { "customField" => { "title" => "Department", "body" => "Updated" } } ]
      execute("input" => { "preview" => false, "operations" => ops })

      field = CustomField.find_by(title: "Department")
      expect(field.validation_options.count).to eq(0)
    end
  end

  describe "preview mode" do
    it "validates without persisting" do
      expect {
        execute("input" => { "preview" => true, "operations" => operations })
      }.not_to change { CustomField.count }
    end

    it "returns a preview result" do
      result = execute("input" => { "preview" => true, "operations" => operations })
      data = result.dig("data", "bulkUpsertCustomFields")

      expect(data["totalRows"]).to eq(2)
      expect(data["validRows"]).to eq(2)
      expect(data["invalidRows"]).to eq(0)
    end

    it "reports validation errors" do
      bad_ops = [ { "customField" => { "title" => "", "body" => "" } } ]
      result = execute("input" => { "preview" => true, "operations" => bad_ops })
      data = result.dig("data", "bulkUpsertCustomFields")

      expect(data["invalidRows"]).to eq(1)
      expect(data["errors"].map { |e| e["field"] }).to include("title", "body")
    end

    context "when a title already exists in the database" do
      before { CustomField.create!(title: "Department", body: "Old body") }

      it "does not flag the existing title as invalid (it will be updated)" do
        result = execute("input" => { "preview" => true, "operations" => operations })
        data = result.dig("data", "bulkUpsertCustomFields")

        expect(data["validRows"]).to eq(2)
        expect(data["invalidRows"]).to eq(0)
      end
    end
  end

  describe "idempotency key" do
    it "returns the existing operation on retry" do
      input = { "preview" => false, "idempotencyKey" => "upsert_001", "operations" => operations }

      first  = execute("input" => input).dig("data", "bulkUpsertCustomFields", "id")
      second = execute("input" => input).dig("data", "bulkUpsertCustomFields", "id")

      expect(first).to eq(second)
      expect(BulkOperation.where(idempotency_key: "upsert_001").count).to eq(1)
    end
  end
end
