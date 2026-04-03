class RenameMealNameAndAddMealToCalorieEntries < ActiveRecord::Migration[8.1]
  def change
    rename_column :calorie_entries, :meal_name, :name
    add_column :calorie_entries, :meal, :integer, null: false, default: 0
    add_index :calorie_entries, :meal
    add_check_constraint :calorie_entries, "meal BETWEEN 0 AND 4", name: "calorie_entries_meal_valid"
  end
end
