class AddUserIdToUserTables < ActiveRecord::Migration[7.2]
  def change
    # user_settings: unique per user (replaces unique-on-user_email)
    add_reference :user_settings,          :user, null: true, foreign_key: true, index: { unique: true }

    # remaining tables: many records per user
    add_reference :assignment_estimates,   :user, null: true, foreign_key: true
    add_reference :study_sessions,         :user, null: true, foreign_key: true
    add_reference :assignment_reestimates, :user, null: true, foreign_key: true
    add_reference :assignment_alerts,      :user, null: true, foreign_key: true
  end
end
