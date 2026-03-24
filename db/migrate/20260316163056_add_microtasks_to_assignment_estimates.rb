class AddMicrotasksToAssignmentEstimates < ActiveRecord::Migration[7.2]
  def change
    add_column :assignment_estimates, :microtasks, :json
  end
end
