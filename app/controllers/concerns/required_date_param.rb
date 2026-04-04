module RequiredDateParam
  extend ActiveSupport::Concern

  included do
    before_action :set_date
  end

  private

  def set_date
    @date = parse_date(params[:date])
    redirect_to(daily_log_path(Date.current), alert: "Invalid date format.") if @date.nil?
  end

  def parse_date(value)
    (value == "today") ? Date.current : Date.iso8601(value)
  rescue ArgumentError, TypeError
    nil
  end
end
