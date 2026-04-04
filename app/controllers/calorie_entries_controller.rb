# frozen_string_literal: true

class CalorieEntriesController < ApplicationController
  def new
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @calorie_entry = CalorieEntry.new(eaten_on: @date, meal: :other)
    render layout: false
  end

  def show
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @calorie_entry = CalorieEntry.find(params[:id])
    return redirect_to(daily_log_path(@date), alert: "Entry not found for this day.") unless @calorie_entry.eaten_on == @date

    render layout: false
  end

  def edit
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @calorie_entry = CalorieEntry.find(params[:id])
    return redirect_to(daily_log_path(@date), alert: "Entry not found for this day.") unless @calorie_entry.eaten_on == @date

    render layout: false
  end

  def create
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @run_ai_analysis = truthy?(params[:run_ai_analysis])
    user_description = params[:user_description].to_s.strip.presence

    @calorie_entry = CalorieEntry.new(calorie_entry_params)
    @calorie_entry.eaten_on = @date
    @calorie_entry.note = user_description if user_description.present?
    if @calorie_entry.save
      @calorie_entry.analyze! if ai_flow_requested?
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_after_create }
      end
    else
      @entry_from_photo_step = image_param_present?
      respond_to do |format|
        format.turbo_stream { render :create, status: :unprocessable_entity }
        format.html do
          redirect_to daily_log_path(@date), alert: @calorie_entry.errors.full_messages.to_sentence
        end
      end
    end
  end

  def update
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @calorie_entry = CalorieEntry.find(params[:id])
    unless @calorie_entry.eaten_on == @date
      return redirect_to(daily_log_path(@date), alert: "Entry not found for this day.")
    end

    was_draft = @calorie_entry.draft?
    @calorie_entry.assign_attributes(calorie_entry_update_params)

    if @calorie_entry.save
      @just_finalized_from_draft = was_draft && @calorie_entry.final?
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to daily_log_path(@date), notice: "Entry saved." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html do
          redirect_to daily_log_path(@date), alert: @calorie_entry.errors.full_messages.to_sentence
        end
      end
    end
  end

  def destroy
    @date = parse_date(params[:date])
    return redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?

    @calorie_entry = CalorieEntry.find(params[:id])
    unless @calorie_entry.eaten_on == @date
      return redirect_to(daily_log_path(@date), alert: "Entry not found for this day.")
    end

    @calorie_entry.destroy!
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to daily_log_path(@date), notice: "Entry deleted." }
    end
  end

  private

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def image_param_present?
    uploaded = params.dig(:calorie_entry, :image)
    uploaded.respond_to?(:present?) && uploaded.present?
  end

  def ai_flow_requested?
    @run_ai_analysis && image_param_present?
  end

  def post_create_ai_metadata!(entry, user_description)
    if ai_flow_requested?
      entry.analyze!
    elsif @run_ai_analysis && !image_param_present?
      entry.merge_ai_metadata!("analysis_status" => "skipped")
      entry.save!
    end
  end

  def redirect_after_create
    if @calorie_entry.draft?
      redirect_to daily_log_path(@date), notice: "Draft ready - review and save."
    else
      redirect_to daily_log_path(@date), notice: "Entry added."
    end
  end

  def calorie_entry_params
    params.require(:calorie_entry).permit(:name, :meal, :calories, :note, :image, :eaten_on)
  end

  def calorie_entry_update_params
    params.require(:calorie_entry).permit(:name, :meal, :calories, :note, :image, :state)
  end

  def parse_date(value)
    value == "today" ? Date.current : Date.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end
end
