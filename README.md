# BulkRails

A Rails 8 demo app exploring standardised bulk mutation patterns via GraphQL. Built around two mutations — `bulkCreateCustomFields` and `bulkUpsertCustomFields` — that share a common base supporting inline operations, URL-based JSON imports, dry-run preview, idempotency, and row-level validation feedback.

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
| `http://localhost:3000/graphiql` | GraphiQL IDE — opens with 5 named example tabs |
| `http://localhost:3000/fixtures/custom_fields` | Fixture endpoint — returns 5–25 random operations as JSON |
| `http://localhost:3000/bulk_operations/:id/results` | Report — rows that succeeded in a completed operation |
| `http://localhost:3000/bulk_operations/:id/errors` | Report — rows that failed with their validation errors |

---

## Running the specs

```sh
bundle exec rspec
```

---

## Data model

```
CustomField
  title:  string   (required, unique)
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
  result_url:       string    — set whenever any rows succeeded (links to /results report)
  error_url:        string    — set whenever any rows failed   (links to /errors  report)
  results_data:     text      — JSON; { successes: [{title,body}], failures: [{title,body,errors}] }
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

# ── Mutations ─────────────────────────────────────────────────────────────

type Mutation {
  # Creates new records — fails if a title already exists
  bulkCreateCustomFields(input: BulkCreateCustomFieldsInput!): BulkCreateCustomFieldsPayload!

  # Creates or updates records matched by title
  bulkUpsertCustomFields(input: BulkCreateCustomFieldsInput!): BulkCreateCustomFieldsPayload!
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

## Mutations

### `bulkCreateCustomFields`

Creates new `CustomField` records. Each row fails independently — a row with a duplicate title will fail while others succeed. The final status reflects whether all, some, or none of the rows succeeded.

### `bulkUpsertCustomFields`

Finds an existing `CustomField` by `title` and updates it, or creates a new one if no match is found. Replaces the associated validation options on update.

Both mutations accept the same input and return the same union type. Both support preview mode, `operationsUrl`, and idempotency.

---

## Execution model

How operations are processed depends on how they are supplied:

| Input | `preview` | Behaviour |
|-------|-----------|-----------|
| `operations` (inline) | `false` | Processed synchronously. Returns a completed `BulkOperationResult` with `result_url` / `error_url`. |
| `operations` (inline) | `true` | Validated synchronously. Returns a `BulkOperationPreviewResult`. Nothing is persisted. |
| `operationsUrl` | `false` | URL format is validated immediately. A `QUEUED` `BulkOperationResult` is returned and an ActiveJob is enqueued. The job fetches the URL, processes rows, and updates the record. |
| `operationsUrl` | `true` | URL is fetched synchronously. Returns an immediate `BulkOperationPreviewResult`. Nothing is persisted. |

### Result reports

After any operation completes (inline or async), the `BulkOperation` record carries:

- **`resultUrl`** — always set when at least one row succeeded, even if the overall status is `COMPLETED`. Points to `/bulk_operations/:id/results`.
- **`errorUrl`** — set when at least one row failed. Points to `/bulk_operations/:id/errors`.

The dashboard links to these pages directly from the operations table.

---

## Preview mode

Setting `preview: true` runs validation on every row without persisting anything. The response is a `BulkOperationPreviewResult` with per-row error details.

Preview runs the full ActiveRecord model validation, which means it catches:
- blank title or body
- duplicate titles (for `bulkCreateCustomFields` — already-existing titles will be flagged)
- `minLength` greater than `maxLength`
- invalid regex patterns

For `bulkUpsertCustomFields`, existing titles are not flagged as errors in preview — they represent rows that will be updated.

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
      errors { rowIndex field message }
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
      errors { rowIndex field message }
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
      resultUrl
      errorUrl
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
      "failedRows": 0,
      "resultUrl": "/bulk_operations/1/results",
      "errorUrl": null
    }
  }
}
```

---

### 4. Upsert — create or update by title

Uses `bulkUpsertCustomFields`. Records matched by `title` are updated; unmatched titles are created. Validation options are replaced on update.

```graphql
mutation {
  bulkUpsertCustomFields(input: {
    preview: false
    operations: [
      {
        customField: { title: "Department", body: "Updated body" }
        validationOptions: { required: true, maxLength: 200 }
      }
      {
        customField: { title: "Brand New Field", body: "Hello" }
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

---

### 5. Live create — URL-based (async)

Point `operationsUrl` at any accessible JSON endpoint. The mutation returns immediately with `QUEUED` status while an ActiveJob fetches the URL and processes rows in the background.

```graphql
mutation {
  bulkCreateCustomFields(input: {
    preview: false
    operationsUrl: "http://localhost:3000/fixtures/custom_fields"
  }) {
    ... on BulkOperationResult {
      id
      status
      resultUrl
      errorUrl
    }
  }
}
```

Immediate response (job not yet run):

```json
{
  "data": {
    "bulkCreateCustomFields": {
      "id": "42",
      "status": "QUEUED",
      "resultUrl": null,
      "errorUrl": null
    }
  }
}
```

Once the job completes, poll with `bulkOperation(id: "42")` — `status` will be `COMPLETED` (or `PARTIALLY_COMPLETED` / `FAILED`) and `resultUrl` / `errorUrl` will be populated.

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

For non-preview URL operations, errors fall into two categories:

**Mutation-level** (synchronous, returned in the GraphQL `errors` array):

| Situation | Error message |
|-----------|--------------|
| Non-HTTP URL (e.g. `ftp://`) | `operationsUrl must be an HTTP or HTTPS URL` |
| Both `operations` and `operationsUrl` given | `Provide either operations or operationsUrl, not both` |

**Job-level** (async, reflected in the `BulkOperation` record as `FAILED` status):

| Situation | Effect |
|-----------|--------|
| HTTP error response | `status` → `FAILED` |
| Response is not valid JSON | `status` → `FAILED` |
| Response is a JSON object, not array | `status` → `FAILED` |

For `preview: true` with a URL, all errors are synchronous and returned in the GraphQL `errors` array.

---

### 6. Preview via URL

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
      errors { rowIndex field message }
    }
  }
}
```

---

### 7. Using both fragments together

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

### 8. Idempotency

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

### 9. Poll job status

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

---

## GraphiQL

`/graphiql` opens with five named tabs, one per example operation:

| Tab | What it does |
|-----|-------------|
| `inlineMutation` | Preview dry-run with inline operations |
| `urlMutation` | Live create via the fixture URL |
| `upsertMutation` | Upsert (create or update) inline operations |
| `wrongMutation` | Error case — both `operations` and `operationsUrl` provided |
| `pollJob` | Poll a job by ID |
