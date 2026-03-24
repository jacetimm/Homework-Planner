class AddCalendarPreferencesToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :block_google_calendar_events, :boolean, default: true, null: false
    add_column :user_settings, :calendar_ignored_keywords, :json, default: [], null: false
  end
end
