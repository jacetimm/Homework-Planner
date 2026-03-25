class CreateUsers < ActiveRecord::Migration[7.2]
  def change
    create_table :users do |t|
      t.string   :email,            null: false
      t.string   :name
      t.string   :avatar_url
      t.string   :google_uid,       null: false
      t.text     :access_token
      t.text     :refresh_token
      t.datetime :token_expires_at
      t.timestamps
    end

    add_index :users, :email,      unique: true
    add_index :users, :google_uid, unique: true
  end
end
