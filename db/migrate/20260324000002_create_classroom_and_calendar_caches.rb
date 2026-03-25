class CreateClassroomAndCalendarCaches < ActiveRecord::Migration[7.2]
  def change
    create_table :classroom_caches do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.json :courses_data, default: []
      t.json :assignments_data, default: []
      t.datetime :synced_at
      t.timestamps
    end

    create_table :calendar_caches do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.json :raw_blocks_data, default: []
      t.datetime :synced_at
      t.timestamps
    end
  end
end
