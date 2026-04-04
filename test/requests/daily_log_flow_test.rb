require "test_helper"

class DailyLogFlowTest < ActionDispatch::IntegrationTest
  test "shows entries for a given day only" do
    date = Date.new(2026, 4, 1)
    CalorieEntry.create!(eaten_on: date, calories: 510, name: "Chicken bowl", meal: :lunch, state: :final)
    CalorieEntry.create!(eaten_on: date - 1, calories: 200, name: "Toast", meal: :breakfast, state: :final)

    get daily_log_path(date)

    assert_response :success
    assert_includes response.body, "Chicken bowl"
    assert_not_includes response.body, "Toast"
  end

  test "invalid date redirects to today's log" do
    get daily_log_path("bad-date")

    assert_redirected_to daily_log_path(Date.current)
  end

  test "daily log header links to previous and next day" do
    date = Date.new(2026, 6, 15)
    get daily_log_path(date)

    assert_response :success
    assert_select "a[href=?]", daily_log_path(date - 1.day), text: /Previous/
    assert_select "a[href=?]", daily_log_path(date + 1.day), text: /Next/
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

  test "turbo create without finalize keeps draft and replaces form frame" do
    date = Date.new(2026, 4, 2)

    post log_entries_path(date: date),
      params: {
        calorie_entry: {
          name: "Pasta",
          meal: "dinner",
          calories: 700
        }
      },
      headers: {"Accept" => Mime[:turbo_stream].to_s}

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_not_includes response.body, 'turbo-stream action="append" target="entries"'
    assert_includes response.body, 'turbo-stream action="replace" target="entry_form"'

    entry = CalorieEntry.order(:created_at).last
    assert entry.draft?
  end

  test "draft entries are hidden from daily log" do
    date = Date.new(2026, 4, 5)
    CalorieEntry.create!(eaten_on: date, calories: 500, name: "Visible", meal: :lunch, state: :final)
    CalorieEntry.create!(eaten_on: date, calories: 1, name: "Hidden draft", meal: :other, state: :draft)

    get daily_log_path(date)

    assert_includes response.body, "Visible"
    assert_not_includes response.body, "Hidden draft"
  end

  test "run_ai_analysis with image creates draft and calls analyzer" do
    date = Date.new(2026, 4, 6)
    fake = FoodPhotoAnalyzer::Result.new(
      success: true,
      attributes: {name: "AI Salad", meal: "lunch", calories: 350, note: "ok"}.with_indifferent_access,
      error_message: nil,
      model: "test"
    )

    with_stubbed_instance_method(FoodPhotoAnalyzer, :call, -> { fake }) do
      assert_difference("CalorieEntry.count", 1) do
        post log_entries_path(date: date),
          params: {
            run_ai_analysis: "1",
            user_description: "no dressing",
            calorie_entry: {
              image: fixture_file_upload("one_pixel.png", "image/png")
            }
          },
          as: :multipart,
          headers: {"Accept" => Mime[:turbo_stream].to_s}
      end
    end

    entry = CalorieEntry.order(:created_at).last
    assert entry.draft?
    assert_equal "completed", entry.analysis_status
    assert_equal "AI Salad", entry.name
    assert_equal 350, entry.calories
    assert_includes entry.note.to_s, "no dressing"
    assert_response :success
    assert_includes response.body, 'turbo-stream action="replace" target="entry_form"'
    assert_not_includes response.body, 'turbo-stream action="append" target="entries"'
  end

  test "run_ai_analysis without image does not call analyzer" do
    date = Date.new(2026, 4, 7)
    with_stubbed_instance_method(FoodPhotoAnalyzer, :call, ->(*) { flunk("AI should not run without an image") }) do
      assert_difference("CalorieEntry.count", 1) do
        post log_entries_path(date: date),
          params: {
            run_ai_analysis: "1",
            calorie_entry: {
              name: "Manual",
              meal: "breakfast",
              calories: 220
            }
          }
      end
    end

    entry = CalorieEntry.order(:created_at).last
    assert entry.draft?
  end

  test "image without run_ai_analysis creates draft without calling analyzer" do
    date = Date.new(2026, 4, 9)
    with_stubbed_instance_method(FoodPhotoAnalyzer, :call, ->(*) { flunk("AI should not run for manual photo flow") }) do
      assert_difference("CalorieEntry.count", 1) do
        post log_entries_path(date: date),
          params: {
            run_ai_analysis: "0",
            user_description: "leftovers",
            calorie_entry: {
              image: fixture_file_upload("one_pixel.png", "image/png")
            }
          },
          as: :multipart,
          headers: {"Accept" => Mime[:turbo_stream].to_s}
      end
    end

    entry = CalorieEntry.order(:created_at).last
    assert entry.draft?
    assert entry.image.attached?
    assert_includes entry.note.to_s, "leftovers"
    assert_response :success
    assert_includes response.body, 'turbo-stream action="replace" target="entry_form"'
    assert_not_includes response.body, 'turbo-stream action="append" target="entries"'
  end

  test "finalize draft appends to log via turbo" do
    date = Date.new(2026, 4, 8)
    draft = CalorieEntry.create!(
      eaten_on: date,
      calories: 1,
      meal: :other,
      state: :draft,
      name: "Temp",
      ai_metadata: {"analysis_status" => "completed"}
    )

    patch log_entry_path(date, draft),
      params: {
        calorie_entry: {
          state: "final",
          name: "Temp",
          meal: "lunch",
          calories: 400,
          note: ""
        }
      },
      headers: {"Accept" => Mime[:turbo_stream].to_s}

    assert_response :success
    draft.reload
    assert draft.final?
    assert_includes response.body, 'turbo-stream action="append" target="entries"'
  end

  test "show entry renders turbo frame with details" do
    date = Date.new(2026, 4, 11)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 400,
      name: "Rice bowl",
      meal: :lunch,
      state: :final,
      note: "extra veggies"
    )

    get log_calorie_entry_path(date, entry)

    assert_response :success
    assert_includes response.body, "Entry details"
    assert_includes response.body, "Rice bowl"
    assert_includes response.body, "extra veggies"
  end

  test "destroy removes entry and resets drawer frame" do
    date = Date.new(2026, 4, 12)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 300,
      name: "Soup",
      meal: :dinner,
      state: :final
    )

    assert_difference("CalorieEntry.count", -1) do
      delete delete_log_calorie_entry_path(date, entry),
        headers: {"Accept" => Mime[:turbo_stream].to_s}
    end

    assert_response :success
    assert_includes response.body, %(action="remove")
    assert_includes response.body, %(target="#{dom_id(entry)}")
    assert_includes response.body, 'turbo-stream action="replace" target="entry_form"'
  end

  test "updating a final entry replaces the row without appending" do
    date = Date.new(2026, 4, 13)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 250,
      name: "Salad",
      meal: :lunch,
      state: :final
    )

    patch log_entry_path(date, entry),
      params: {
        calorie_entry: {
          name: "Big salad",
          meal: "lunch",
          calories: 280,
          note: ""
        }
      },
      headers: {"Accept" => Mime[:turbo_stream].to_s}

    assert_response :success
    assert_not_includes response.body, 'turbo-stream action="append" target="entries"'
    assert_includes response.body, %(action="replace" target="#{dom_id(entry)}")
    entry.reload
    assert_equal "Big salad", entry.name
    assert_equal 280, entry.calories
  end
end
