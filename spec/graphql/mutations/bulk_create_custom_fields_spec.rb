require "rails_helper"

RSpec.describe "bulkCreateCustomFields mutation" do
  let(:schema) { BulkrailsSchema }

  def execute(variables = {})
    schema.execute(
      mutation_string,
      variables: variables,
      context: {}
    )
  end

  let(:mutation_string) do
    <<~GQL
      mutation BulkCreateCustomFields($input: BulkCreateCustomFieldsInput!) {
        bulkCreateCustomFields(input: $input) {
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

  let(:valid_operations) do
    [
      {
        "customField" => { "title" => "Department", "body" => "Engineering" },
        "validationOptions" => { "required" => true, "maxLength" => 100 }
      },
      {
        "customField" => { "title" => "Cost Centre", "body" => "CC-404" },
        "validationOptions" => { "required" => true, "pattern" => "^CC-\\d{3}$" }
      },
      {
        "customField" => { "title" => "Travel Tier", "body" => "Premium" },
        "validationOptions" => { "allowedValues" => [ "Standard", "Premium", "Executive" ] }
      }
    ]
  end

  describe "preview mode" do
    context "with all valid operations" do
      it "returns a preview result with no errors" do
        result = execute("input" => { "preview" => true, "operations" => valid_operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["totalRows"]).to eq(3)
        expect(data["validRows"]).to eq(3)
        expect(data["invalidRows"]).to eq(0)
        expect(data["errors"]).to be_empty
      end

      it "does not persist any records" do
        expect {
          execute("input" => { "preview" => true, "operations" => valid_operations })
        }.not_to change { CustomField.count }
      end
    end

    context "with a blank title" do
      let(:operations) do
        [ { "customField" => { "title" => "", "body" => "Some body" } } ]
      end

      it "reports a row-level error for the title field" do
        result = execute("input" => { "preview" => true, "operations" => operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["invalidRows"]).to eq(1)
        error = data["errors"].find { |e| e["field"] == "title" }
        expect(error).to be_present
        expect(error["rowIndex"]).to eq(0)
      end
    end

    context "with minLength greater than maxLength" do
      let(:operations) do
        [ {
          "customField" => { "title" => "Field", "body" => "body" },
          "validationOptions" => { "minLength" => 50, "maxLength" => 10 }
        } ]
      end

      it "reports a validation error for min_length" do
        result = execute("input" => { "preview" => true, "operations" => operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["invalidRows"]).to eq(1)
        error = data["errors"].find { |e| e["field"] == "min_length" }
        expect(error).to be_present
      end
    end

    context "with an invalid regex pattern" do
      let(:operations) do
        [ {
          "customField" => { "title" => "Field", "body" => "body" },
          "validationOptions" => { "pattern" => "[invalid regex" }
        } ]
      end

      it "reports a pattern validation error" do
        result = execute("input" => { "preview" => true, "operations" => operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["invalidRows"]).to eq(1)
        error = data["errors"].find { |e| e["field"] == "pattern" }
        expect(error).to be_present
      end
    end

    context "when a title already exists in the database" do
      before { CustomField.create!(title: "Department", body: "Old body") }

      it "reports a uniqueness error for the duplicate title" do
        result = execute("input" => { "preview" => true, "operations" => valid_operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["invalidRows"]).to eq(1)
        error = data["errors"].find { |e| e["field"] == "title" }
        expect(error).to be_present
        expect(error["rowIndex"]).to eq(0)
      end

      it "still reports the remaining rows as valid" do
        result = execute("input" => { "preview" => true, "operations" => valid_operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["validRows"]).to eq(2)
      end
    end

    context "with multiple rows, some invalid" do
      let(:operations) do
        [
          { "customField" => { "title" => "Valid", "body" => "body" } },
          { "customField" => { "title" => "", "body" => "body" } },
          { "customField" => { "title" => "Also Valid", "body" => "body" } },
          { "customField" => { "title" => "", "body" => "" } }
        ]
      end

      it "correctly counts valid and invalid rows" do
        result = execute("input" => { "preview" => true, "operations" => operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["totalRows"]).to eq(4)
        expect(data["validRows"]).to eq(2)
        expect(data["invalidRows"]).to eq(2)
      end
    end
  end

  describe "live create mode" do
    context "with all valid operations" do
      it "creates a completed BulkOperation" do
        result = execute("input" => { "preview" => false, "operations" => valid_operations })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["status"]).to eq("COMPLETED")
        expect(data["totalRows"]).to eq(3)
        expect(data["successfulRows"]).to eq(3)
        expect(data["failedRows"]).to eq(0)
      end

      it "persists all CustomField records" do
        expect {
          execute("input" => { "preview" => false, "operations" => valid_operations })
        }.to change { CustomField.count }.by(3)
      end

      it "persists validation options alongside custom fields" do
        execute("input" => { "preview" => false, "operations" => valid_operations })
        field = CustomField.find_by(title: "Cost Centre")

        expect(field).to be_present
        expect(field.validation_options.first.pattern).to eq("^CC-\\d{3}$")
      end

      it "persists allowed_values as an array" do
        execute("input" => { "preview" => false, "operations" => valid_operations })
        field = CustomField.find_by(title: "Travel Tier")

        expect(field.validation_options.first.allowed_values).to eq([ "Standard", "Premium", "Executive" ])
      end
    end

    context "with idempotency key" do
      it "returns the existing operation on retry" do
        input = { "preview" => false, "idempotencyKey" => "key_abc", "operations" => valid_operations }

        first  = execute("input" => input).dig("data", "bulkCreateCustomFields", "id")
        second = execute("input" => input).dig("data", "bulkCreateCustomFields", "id")

        expect(first).to eq(second)
        expect(BulkOperation.where(idempotency_key: "key_abc").count).to eq(1)
      end
    end

    context "with no operations" do
      it "creates a completed BulkOperation with zero rows" do
        result = execute("input" => { "preview" => false, "operations" => [] })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["status"]).to eq("COMPLETED")
        expect(data["totalRows"]).to eq(0)
        expect(data["successfulRows"]).to eq(0)
      end
    end
  end

  describe "bulkOperation query" do
    let(:query_string) do
      <<~GQL
        query BulkOperation($id: ID!) {
          bulkOperation(id: $id) {
            id
            status
            totalRows
            successfulRows
            failedRows
          }
        }
      GQL
    end

    it "retrieves a bulk operation by id" do
      create_result = execute("input" => { "preview" => false, "operations" => valid_operations })
      op_id = create_result.dig("data", "bulkCreateCustomFields", "id")

      query_result = schema.execute(query_string, variables: { "id" => op_id }, context: {})
      data = query_result.dig("data", "bulkOperation")

      expect(data["id"]).to eq(op_id)
      expect(data["status"]).to eq("COMPLETED")
    end

    it "returns nil for a non-existent id" do
      query_result = schema.execute(query_string, variables: { "id" => "99999" }, context: {})
      expect(query_result.dig("data", "bulkOperation")).to be_nil
    end
  end

  describe "operationsUrl" do
    let(:operations_url) { "https://storage.example.com/uploads/custom_fields.json" }

    let(:valid_json) do
      [
        {
          "customField" => { "title" => "Department", "body" => "Engineering" },
          "validationOptions" => { "required" => true, "maxLength" => 100 }
        },
        {
          "customField" => { "title" => "Cost Centre", "body" => "CC-404" },
          "validationOptions" => { "pattern" => "^CC-\\d{3}$" }
        }
      ].to_json
    end

    context "with preview: false (async path)" do
      it "returns a QUEUED BulkOperation immediately without fetching the URL" do
        result = execute("input" => { "preview" => false, "operationsUrl" => operations_url })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(result["errors"]).to be_nil
        expect(data["status"]).to eq("QUEUED")
      end

      it "enqueues a BulkCreateCustomFieldsJob" do
        expect {
          execute("input" => { "preview" => false, "operationsUrl" => operations_url })
        }.to have_enqueued_job(BulkCreateCustomFieldsJob)
      end

      it "does not persist any records synchronously" do
        expect {
          execute("input" => { "preview" => false, "operationsUrl" => operations_url })
        }.not_to change { CustomField.count }
      end

      context "when the job runs" do
        before do
          stub_request(:get, operations_url).to_return(
            status: 200,
            body: valid_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "processes the operations and marks the BulkOperation COMPLETED" do
          perform_enqueued_jobs do
            execute("input" => { "preview" => false, "operationsUrl" => operations_url })
          end

          bulk_op = BulkOperation.last
          expect(bulk_op.status).to eq("completed")
          expect(bulk_op.successful_rows).to eq(2)
          expect(bulk_op.failed_rows).to eq(0)
        end

        it "persists the custom fields" do
          expect {
            perform_enqueued_jobs do
              execute("input" => { "preview" => false, "operationsUrl" => operations_url })
            end
          }.to change { CustomField.count }.by(2)
        end
      end
    end

    context "with preview: true (synchronous path)" do
      before do
        stub_request(:get, operations_url).to_return(
          status: 200,
          body: valid_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "fetches the URL and returns an immediate preview result" do
        result = execute("input" => { "preview" => true, "operationsUrl" => operations_url })
        data = result.dig("data", "bulkCreateCustomFields")

        expect(data["totalRows"]).to eq(2)
        expect(data["validRows"]).to eq(2)
        expect(data["invalidRows"]).to eq(0)
      end

      it "does not persist any records" do
        expect {
          execute("input" => { "preview" => true, "operationsUrl" => operations_url })
        }.not_to change { CustomField.count }
      end
    end

    context "when both operations and operationsUrl are provided" do
      it "returns an error" do
        result = execute("input" => {
          "operationsUrl" => operations_url,
          "operations" => [ { "customField" => { "title" => "X", "body" => "Y" } } ]
        })

        expect(result["errors"]).to be_present
        expect(result["errors"].first["message"]).to match(/not both/)
      end
    end

    context "when a non-HTTP URL is provided" do
      it "returns an execution error immediately (before enqueueing)" do
        result = execute("input" => { "preview" => false, "operationsUrl" => "ftp://example.com/file.json" })
        expect(result["errors"].first["message"]).to match(/HTTP or HTTPS/)
      end
    end

    # HTTP-level and JSON errors surface via the job — tested in spec/jobs/
    context "when the URL returns a non-200 status (preview path)" do
      before { stub_request(:get, operations_url).to_return(status: 404, body: "Not Found") }

      it "returns an execution error" do
        result = execute("input" => { "preview" => true, "operationsUrl" => operations_url })
        expect(result["errors"].first["message"]).to match(/HTTP 404/)
      end
    end

    context "when the URL returns invalid JSON (preview path)" do
      before { stub_request(:get, operations_url).to_return(status: 200, body: "not json") }

      it "returns an execution error" do
        result = execute("input" => { "preview" => true, "operationsUrl" => operations_url })
        expect(result["errors"].first["message"]).to match(/valid JSON/)
      end
    end

    context "when the URL returns a JSON object instead of an array (preview path)" do
      before { stub_request(:get, operations_url).to_return(status: 200, body: '{"foo":"bar"}') }

      it "returns an execution error" do
        result = execute("input" => { "preview" => true, "operationsUrl" => operations_url })
        expect(result["errors"].first["message"]).to match(/JSON array/)
      end
    end
  end
end
