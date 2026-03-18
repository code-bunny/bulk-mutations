module Types
  class BulkOperationStatusEnum < Types::BaseEnum
    value "CREATED", value: "created"
    value "VALIDATING", value: "validating"
    value "QUEUED", value: "queued"
    value "RUNNING", value: "running"
    value "PARTIALLY_COMPLETED", value: "partially_completed"
    value "COMPLETED", value: "completed"
    value "FAILED", value: "failed"
    value "CANCELLED", value: "cancelled"
  end
end
