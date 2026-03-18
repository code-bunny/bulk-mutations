class BulkOperation < ApplicationRecord
  serialize :results_data, coder: JSON

  enum :status, {
    created: 0,
    validating: 1,
    queued: 2,
    running: 3,
    partially_completed: 4,
    completed: 5,
    failed: 6,
    cancelled: 7
  }
end
