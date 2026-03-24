class AddCalendarIgnoreRulesToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :ignored_google_calendar_ids, :json, default: [], null: false
    add_column :user_settings, :calendar_ignore_rules, :json, default: [], null: false
  end
end
