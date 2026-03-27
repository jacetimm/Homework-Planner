class AddColorThemeToUserSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :user_settings, :color_theme, :string, default: "auto", null: false
  end
end
