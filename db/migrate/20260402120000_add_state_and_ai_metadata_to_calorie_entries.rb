# frozen_string_literal: true

class AddStateAndAiMetadataToCalorieEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :calorie_entries, :state, :integer, null: false, default: 1
    add_column :calorie_entries, :ai_metadata, :jsonb, null: false, default: {}

    add_index :calorie_entries, :state
  end
end
