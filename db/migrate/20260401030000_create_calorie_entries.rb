class CreateCalorieEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :calorie_entries do |t|
      t.date :eaten_on, null: false
      t.string :meal_name
      t.integer :calories, null: false
      t.text :note

      t.timestamps
    end

    add_index :calorie_entries, :eaten_on
    add_index :calorie_entries, %i[eaten_on created_at]
  end
end
