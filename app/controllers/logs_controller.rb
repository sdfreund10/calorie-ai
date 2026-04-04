class LogsController < ApplicationController
  include RequiredDateParam

  def show
    @entries = CalorieEntry.finalized.for_day(@date).order(created_at: :asc)
    @calorie_entry = CalorieEntry.new(eaten_on: @date, meal: :other)
    @calorie_total = @entries.sum(:calories)
  end
end
