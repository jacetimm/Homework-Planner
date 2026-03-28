class CreateHiddenAssignments < ActiveRecord::Migration[7.2]
  def change
    create_table :hidden_assignments do |t|
      t.references :user, null: false, foreign_key: true
      t.string :course_work_id, null: false
      t.string :course_name
      t.string :assignment_title
      t.datetime :hidden_at

      t.timestamps
    end
    add_index :hidden_assignments, [:user_id, :course_work_id], unique: true
  end
end
