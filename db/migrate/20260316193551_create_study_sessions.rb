class CreateStudySessions < ActiveRecord::Migration[7.2]
  def change
    create_table :study_sessions do |t|
      t.string  :course_work_id,   null: false
      t.string  :user_email,       null: false
      t.string  :assignment_title, null: false
      t.string  :course_name
      t.integer :estimated_minutes
      t.integer :actual_minutes
      t.datetime :started_at

      t.timestamps
    end

    add_index :study_sessions, [ :user_email, :course_work_id ]
  end
end
