class RenameMealNameAndAddMealToCalorieEntries < ActiveRecord::Migration[8.1]
  def change
    rename_column :calorie_entries, :meal_name, :name
    add_column :calorie_entries, :meal, :integer, null: false, default: 0
    add_index :calorie_entries, :meal
  end
end
