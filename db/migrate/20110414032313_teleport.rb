class Teleport < ActiveRecord::Migration
  def self.up
    change_table(:candidates) do |t|
      t.string :__key
    end
  end

  def self.down
    remove_column :candidates, :__key
  end
end
