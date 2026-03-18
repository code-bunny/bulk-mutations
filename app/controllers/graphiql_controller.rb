class GraphiqlController < ApplicationController
  layout false
  skip_before_action :verify_authenticity_token, raise: false

  TABS = [
    {
      title: "Preview Inline",
      query: <<~GQL
        # Dry-run: validates operations without persisting anything
        mutation inlineMutation {
          bulkCreateCustomFields(input: {
            preview: true
            operations: [
              {
                customField: { title: "Department", body: "Engineering" }
                validationOptions: { required: true, maxLength: 100 }
              }
              {
                customField: { title: "Cost Centre", body: "CC-404" }
                validationOptions: { required: true, pattern: "^CC-\\\\d{3}$" }
              }
              {
                customField: { title: "Travel Tier", body: "Premium" }
                validationOptions: { allowedValues: ["Standard", "Premium", "Executive"] }
              }
            ]
          }) {
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
              errors { rowIndex field message }
            }
          }
        }
      GQL
    },
    {
      title: "Create via URL",
      query: <<~GQL
        # Live create: fetches random 5-25 fields from the fixture endpoint
        mutation urlMutation {
          bulkCreateCustomFields(input: {
            preview: false
            operationsUrl: "http://localhost:3000/fixtures/custom_fields"
          }) {
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
              errors { rowIndex field message }
            }
          }
        }
      GQL
    },
    {
      title: "Upsert (create or update)",
      query: <<~GQL
        # Upsert: finds existing record by title or creates a new one
        mutation upsertMutation {
          bulkUpsertCustomFields(input: {
            preview: false
            operations: [
              {
                customField: { title: "Department", body: "Updated body" }
                validationOptions: { required: true, maxLength: 200 }
              }
              {
                customField: { title: "New Field", body: "Brand new" }
              }
            ]
          }) {
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
              errors { rowIndex field message }
            }
          }
        }
      GQL
    },
    {
      title: "Error Case",
      query: <<~GQL
        # Error: providing both operations and operationsUrl raises an error
        mutation wrongMutation {
          bulkCreateCustomFields(input: {
            preview: false
            operationsUrl: "http://localhost:3000/fixtures/custom_fields"
            operations: [
              {
                customField: { title: "Department", body: "Engineering" }
              }
            ]
          }) {
            ... on BulkOperationResult {
              id status
            }
            ... on BulkOperationPreviewResult {
              totalRows validRows invalidRows
            }
          }
        }
      GQL
    },
    {
      title: "Poll Job",
      query: <<~GQL
        # Poll a job by ID — replace "1" with an id from a live create result
        query pollJob {
          bulkOperation(id: "1") {
            id
            status
            totalRows
            processedRows
            successfulRows
            failedRows
            resultUrl
            errorUrl
            createdAt
            startedAt
            completedAt
          }
        }
      GQL
    }
  ].freeze

  def index
    @tabs = TABS
    @graphql_path = "/graphql"
  end
end
