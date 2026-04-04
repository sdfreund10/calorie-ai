class CalorieEntriesController < ApplicationController
  def create
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @calorie_entry = CalorieEntry.new(calorie_entry_params)
    @calorie_entry.eaten_on = @date

    if @calorie_entry.save
      @new_calorie_entry = CalorieEntry.new(eaten_on: @date, meal: :other)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to daily_log_path(@date), notice: "Entry added." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html do
          redirect_to daily_log_path(@date), alert: @calorie_entry.errors.full_messages.to_sentence
        end
      end
    end
  end

  private

  def calorie_entry_params
    params.require(:calorie_entry).permit(:name, :meal, :calories, :note, :image, :eaten_on)
  end

  def parse_date(value)
    Date.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end
end
