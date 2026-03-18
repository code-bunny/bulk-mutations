class BulkOperationsController < ApplicationController
  before_action :set_bulk_operation

  def results
    @rows = (@bulk_operation.results_data&.dig("successes") || [])
  end

  def errors
    @rows = (@bulk_operation.results_data&.dig("failures") || [])
  end

  private

  def set_bulk_operation
    @bulk_operation = BulkOperation.find(params[:id])
  end
end
