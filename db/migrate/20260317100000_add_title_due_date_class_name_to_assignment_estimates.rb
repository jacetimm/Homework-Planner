class AddTitleDueDateClassNameToAssignmentEstimates < ActiveRecord::Migration[7.2]
  def change
    add_column :assignment_estimates, :title,      :string
    add_column :assignment_estimates, :due_date,   :date
    add_column :assignment_estimates, :class_name, :string
  end
end
