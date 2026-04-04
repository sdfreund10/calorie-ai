class LogsController < ApplicationController
  def show
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @entries = CalorieEntry.finalized.for_day(@date).order(created_at: :asc)
    @calorie_entry = CalorieEntry.new(eaten_on: @date, meal: :other)
    @calorie_total = @entries.sum(:calories)
  end

  private

  def parse_date(value)
    value == "today" ? Date.current : Date.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end
end
