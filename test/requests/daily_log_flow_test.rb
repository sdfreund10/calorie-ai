require "test_helper"

class DailyLogFlowTest < ActionDispatch::IntegrationTest
  test "shows entries for a given day only" do
    date = Date.new(2026, 4, 1)
    CalorieEntry.create!(eaten_on: date, calories: 510, name: "Chicken bowl", meal: :lunch)
    CalorieEntry.create!(eaten_on: date - 1, calories: 200, name: "Toast", meal: :breakfast)

    get daily_log_path(date)

    assert_response :success
    assert_includes response.body, "Chicken bowl"
    assert_not_includes response.body, "Toast"
  end

  test "invalid date redirects to today's log" do
    get daily_log_path("bad-date")

    assert_redirected_to daily_log_path(Date.current)
  end

  test "html create redirects to the same day log" do
    date = Date.new(2026, 4, 2)

    assert_difference("CalorieEntry.count", 1) do
      post log_entries_path(date: date), params: {
        calorie_entry: {
          name: "Oatmeal",
          meal: "breakfast",
          calories: 320,
          note: "banana and peanut butter"
        }
      }
    end

    entry = CalorieEntry.order(:created_at).last
    assert_equal date, entry.eaten_on
    assert_redirected_to daily_log_path(date)
  end

  test "turbo create appends entry and replaces form frame" do
    date = Date.new(2026, 4, 2)

    post log_entries_path(date: date),
         params: {
           calorie_entry: {
             name: "Pasta",
             meal: "dinner",
             calories: 700
           }
         },
         headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_includes response.body, 'turbo-stream action="append" target="entries"'
    assert_includes response.body, 'turbo-stream action="replace" target="entry_form"'
  end
end
