class AddMaxMinutesPerSubjectToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :max_minutes_per_subject, :integer, default: 45
  end
end
