class CreateAssignmentReestimates < ActiveRecord::Migration[7.2]
  def change
    create_table :assignment_reestimates do |t|
      t.string :course_work_id, null: false
      t.string :user_email, null: false

      t.timestamps
    end

    add_index :assignment_reestimates, [ :user_email, :created_at ]
    add_index :assignment_reestimates, [ :user_email, :course_work_id ]
  end
end
