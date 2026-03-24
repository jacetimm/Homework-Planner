class CreateAssignmentEstimates < ActiveRecord::Migration[7.2]
  def change
    create_table :assignment_estimates do |t|
      t.string :course_work_id, null: false
      t.string :user_email,     null: false
      t.integer :estimated_minutes, null: false
      t.string :reasoning

      t.timestamps
    end

    add_index :assignment_estimates, [ :course_work_id, :user_email ], unique: true
  end
end
