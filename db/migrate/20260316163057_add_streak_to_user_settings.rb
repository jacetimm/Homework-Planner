class AddStreakToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :streak_count, :integer, default: 0, null: false
    add_column :user_settings, :streak_last_date, :date
  end
end
