class CreateAssignmentAlerts < ActiveRecord::Migration[7.2]
  def change
    create_table :assignment_alerts do |t|
      t.string   :user_email,     null: false
      t.string   :course_work_id, null: false
      t.string   :alert_type,     null: false, default: "urgent_reminder"
      t.datetime :sent_at,        null: false
      t.timestamps
    end
    add_index :assignment_alerts, [ :user_email, :course_work_id, :alert_type, :sent_at ],
              name: "idx_assignment_alerts_dedup"
  end
end
