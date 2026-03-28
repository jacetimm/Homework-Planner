class CreatePushSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.text :endpoint, null: false
      t.text :p256dh_key, null: false
      t.text :auth_key, null: false
      t.timestamps
    end

    add_index :push_subscriptions, [ :user_id, :endpoint ], unique: true, name: "index_push_subscriptions_on_user_id_and_endpoint"

    add_column :user_settings, :push_notifications_enabled, :boolean, default: true, null: false
  end
end
