class AddMaterialsMetadataToAssignmentEstimates < ActiveRecord::Migration[7.2]
  def change
    add_column :assignment_estimates, :materials_metadata, :json
  end
end
