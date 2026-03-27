class AddOnboardingAndFeatureFlagsToUserSettings < ActiveRecord::Migration[7.2]
  def change
    # default: true so existing users skip onboarding; new users get false via set_defaults
    add_column :user_settings, :onboarding_completed, :boolean, default: true, null: false
    add_column :user_settings, :show_all_features,    :boolean, default: false, null: false
    add_column :user_settings, :visits_count,          :integer, default: 0,   null: false
    add_column :user_settings, :first_visited_at,      :datetime
    add_column :user_settings, :last_visit_date,       :date
  end
end
