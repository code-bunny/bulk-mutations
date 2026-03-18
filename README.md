# BulkRails

A Rails 8 demo app exploring standardised bulk update patterns via GraphQL. Built around a `bulkCreateCustomFields` mutation that supports inline operations, file-based imports via URL, dry-run preview, idempotency, and row-level validation feedback.

---

## Setup

```sh
bundle install
bin/rails db:migrate
bin/rails server
```

| URL | What it is |
|-----|------------|
| `http://localhost:3000` | Dashboard — live view of bulk operations and custom fields |
| `http://localhost:3000/graphiql` | GraphiQL IDE — try mutations interactively |
| `http://localhost:3000/fixtures/custom_fields` | Fixture endpoint — returns 5–25 random operations as JSON |

---

## Running the specs

```sh
bundle exec rspec
```

---

## Data model

```
CustomField
  title:  string   (required)
  body:   text     (required)

CustomFieldValidationOption  (belongs_to CustomField)
  required:       boolean
  min_length:     integer
  max_length:     integer
  pattern:        string   (regex, validated server-side)
  allowed_values: text     (serialised JSON array)

BulkOperation
  status:           enum (see below)
  total_rows:       integer
  processed_rows:   integer
  successful_rows:  integer
  failed_rows:      integer
  idempotency_key:  string
  result_url:       string
  error_url:        string
  started_at:       datetime
  completed_at:     datetime
```

---

## GraphQL schema

```graphql
# ── Inputs ──────────────────────────────────────────────────────────────

input BulkCreateCustomFieldsInput {
  operations:      [CreateCustomFieldWithValidationInput!]
  operationsUrl:   String       # URL to a JSON file (mutually exclusive with operations)
  preview:         Boolean      # default: false — set true for a dry-run
  idempotencyKey:  String       # optional — prevents duplicate jobs on retry
}

input CreateCustomFieldWithValidationInput {
  customField:       CreateCustomFieldInput!
  validationOptions: CustomFieldValidationOptionsInput
}

input CreateCustomFieldInput {
  title: String!
  body:  String!
}

input CustomFieldValidationOptionsInput {
  required:      Boolean
  minLength:     Int
  maxLength:     Int
  pattern:       String     # regex — validated server-side
  allowedValues: [String!]  # body must be one of these values
}

# ── Return types ─────────────────────────────────────────────────────────

union BulkCreateCustomFieldsPayload = BulkOperationResult | BulkOperationPreviewResult

# Returned when preview: false
type BulkOperationResult {
  id:             ID!
  status:         BulkOperationStatus!
  totalRows:      Int
  processedRows:  Int
  successfulRows: Int
  failedRows:     Int
  resultUrl:      String
  errorUrl:       String
  createdAt:      ISO8601DateTime!
  startedAt:      ISO8601DateTime
  completedAt:    ISO8601DateTime
}

# Returned when preview: true
type BulkOperationPreviewResult {
  totalRows:   Int!
  validRows:   Int!
  invalidRows: Int!
  errors:      [RowError!]!
}

type RowError {
  rowIndex: Int!
  sheet:    String
  field:    String
  message:  String!
}

enum BulkOperationStatus {
  CREATED
  VALIDATING
  QUEUED
  RUNNING
  PARTIALLY_COMPLETED
  COMPLETED
  FAILED
  CANCELLED
}

# ── Mutation ─────────────────────────────────────────────────────────────

type Mutation {
  bulkCreateCustomFields(input: BulkCreateCustomFieldsInput!): BulkCreateCustomFieldsPayload!
}

# ── Query ─────────────────────────────────────────────────────────────────

type Query {
  bulkOperation(id: ID!): BulkOperation
}

# Full tracking type — used for polling after a live create
type BulkOperation {
  id:             ID!
  status:         BulkOperationStatus!
  totalRows:      Int
  processedRows:  Int
  successfulRows: Int
  failedRows:     Int
  resultUrl:      String
  errorUrl:       String
  createdAt:      ISO8601DateTime!
  startedAt:      ISO8601DateTime
  completedAt:    ISO8601DateTime
}
```

---

## Examples

### 1. Preview (dry-run) — inline operations

Validates every row without writing anything. Safe to call repeatedly.

```graphql
mutation {
  bulkCreateCustomFields(input: {
    preview: true
    operations: [
      {
        customField: { title: "Department", body: "Engineering" }
        validationOptions: { required: true, maxLength: 100 }
      }
      {
        customField: { title: "Cost Centre", body: "CC-404" }
        validationOptions: { required: true, pattern: "^CC-\\d{3}$" }
      }
      {
        customField: { title: "Travel Tier", body: "Premium" }
        validationOptions: { allowedValues: ["Standard", "Premium", "Executive"] }
      }
    ]
  }) {
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
```

Response:

```json
{
  "data": {
    "bulkCreateCustomFields": {
      "totalRows": 3,
      "validRows": 3,
      "invalidRows": 0,
      "errors": []
    }
  }
}
```

---

### 2. Preview with validation errors

```graphql
mutation {
  bulkCreateCustomFields(input: {
    preview: true
    operations: [
      {
        customField: { title: "", body: "Engineering" }
        validationOptions: { minLength: 50, maxLength: 10 }
      }
      {
        customField: { title: "Cost Centre", body: "CC-404" }
        validationOptions: { pattern: "[invalid regex" }
      }
    ]
  }) {
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
```

Response:

```json
{
  "data": {
    "bulkCreateCustomFields": {
      "totalRows": 2,
      "validRows": 0,
      "invalidRows": 2,
      "errors": [
        { "rowIndex": 0, "field": "title",      "message": "Title can't be blank" },
        { "rowIndex": 0, "field": "min_length",  "message": "min_length cannot exceed max_length" },
        { "rowIndex": 1, "field": "pattern",     "message": "Pattern is not a valid regular expression" }
      ]
    }
  }
}
```

---

### 3. Live create — inline operations

Persists all records and returns a result with row counts.

```graphql
mutation {
  bulkCreateCustomFields(input: {
    preview: false
    idempotencyKey: "import_001"
    operations: [
      {
        customField: { title: "Department", body: "Engineering" }
        validationOptions: { required: true, maxLength: 100 }
      }
      {
        customField: { title: "Cost Centre", body: "CC-404" }
        validationOptions: { required: true, pattern: "^CC-\\d{3}$" }
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
  }
}
```

Response:

```json
{
  "data": {
    "bulkCreateCustomFields": {
      "id": "1",
      "status": "COMPLETED",
      "totalRows": 3,
      "successfulRows": 3,
      "failedRows": 0
    }
  }
}
```

---

### 4. Live create — URL-based

Point `operationsUrl` at any accessible JSON endpoint. The server fetches, parses, and processes it.

```graphql
mutation {
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
  }
}
```

The fixture endpoint (`/fixtures/custom_fields`) returns 5–25 randomly generated operations on every request — useful for testing. Any hosted JSON file works in its place.

#### JSON file format

The file must be a top-level array. Both camelCase and snake_case keys are accepted:

```json
[
  {
    "customField": { "title": "Department", "body": "Engineering" },
    "validationOptions": { "required": true, "maxLength": 100 }
  },
  {
    "customField": { "title": "Cost Centre", "body": "CC-404" },
    "validationOptions": { "pattern": "^CC-\\d{3}$" }
  },
  {
    "custom_field": { "title": "Region", "body": "EMEA" },
    "validation_options": { "allowed_values": ["EMEA", "APAC", "AMER"] }
  }
]
```

#### URL errors

Execution errors are returned (not HTTP errors) so they appear in the GraphQL `errors` array:

| Situation | Error message |
|-----------|--------------|
| Non-HTTP URL (e.g. `ftp://`) | `operationsUrl must be an HTTP or HTTPS URL` |
| HTTP error response | `Failed to fetch operationsUrl (HTTP 404)` |
| Response is not valid JSON | `operationsUrl did not return valid JSON: ...` |
| Response is a JSON object, not array | `operationsUrl must return a JSON array` |
| Both `operations` and `operationsUrl` given | `Provide either operations or operationsUrl, not both` |

---

### 5. Preview via URL

`preview: true` works with `operationsUrl` too — validates without persisting.

```graphql
mutation {
  bulkCreateCustomFields(input: {
    preview: true
    operationsUrl: "http://localhost:3000/fixtures/custom_fields"
  }) {
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
```

---

### 6. Using both fragments together

When `preview` is a variable, one query handles both cases:

```graphql
mutation BulkCreate($input: BulkCreateCustomFieldsInput!) {
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
      errors { rowIndex field message }
    }
  }
}
```

---

### 7. Idempotency

Passing the same `idempotencyKey` on a retry returns the original operation instead of creating a new one. Safe to retry on network failure.

```graphql
mutation {
  bulkCreateCustomFields(input: {
    preview: false
    idempotencyKey: "import_2026_03_18_01"
    operations: [...]
  }) {
    ... on BulkOperationResult { id status }
  }
}
```

---

### 8. Poll job status

Use the `id` from a live create result to query the full operation record:

```graphql
query {
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
```
