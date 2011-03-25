class CreateCandidates < ActiveRecord::Migration
  def self.up
    create_table :candidates do |t|
      t.String :name
      t.String :address
      t.integer :phone
      t.String :occupation

      t.timestamps
    end
  end

  def self.down
    drop_table :candidates
  end
end
