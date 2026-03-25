class AddTimezoneToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :timezone, :string, default: "Eastern Time (US & Canada)", null: false
  end
end
