class CreateUserSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :user_settings do |t|
      t.string :user_email
      t.time :study_start_time
      t.time :study_end_time
      t.integer :break_frequency
      t.integer :break_duration
      t.json :hard_subjects
      t.json :extracurricular_blocks

      t.timestamps
    end
    add_index :user_settings, :user_email
  end
end
