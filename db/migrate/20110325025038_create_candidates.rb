class CreateCandidates < ActiveRecord::Migration
  def self.up
    create_table :candidates do |t|
      t.string :name
      t.string :address
      t.integer :phone
      t.string :occupation

      t.timestamps
    end
  end

  def self.down
    drop_table :candidates
  end
end
