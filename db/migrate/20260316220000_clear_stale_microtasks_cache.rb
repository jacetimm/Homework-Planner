class ClearStaleMicrotasksCache < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE assignment_estimates
      SET microtasks = NULL
      WHERE microtasks IS NOT NULL
    SQL
  end

  def down
    # Irreversible data cleanup.
  end
end
