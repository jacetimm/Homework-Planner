class AddMetadataToAssignmentEstimates < ActiveRecord::Migration[7.2]
  def change
    add_column :assignment_estimates, :description,     :text
    add_column :assignment_estimates, :materials_count, :integer, default: 0, null: false
    add_column :assignment_estimates, :max_points,      :integer
  end
end
