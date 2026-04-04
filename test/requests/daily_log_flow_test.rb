# frozen_string_literal: true

require "test_helper"

class DailyLogFlowTest < ActionDispatch::IntegrationTest
  INVALID_NAME_81 = ("n" * 81).freeze
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
    stub_food_photo_analyzer_call(
      content: {name: "AI Salad", meal: "lunch", calories: 350, note: "ok"}
    ) do
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
    refute_food_photo_analyzer_called("AI should not run without an image") do
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
    refute_food_photo_analyzer_called("AI should not run for manual photo flow") do
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

  test "root redirects to today log path" do
    get root_path

    assert_redirected_to daily_log_path("today")
  end

  test "daily log accepts today alias" do
    get daily_log_path("today")

    assert_response :success
  end

  test "new entry form with invalid date redirects" do
    get new_log_entry_path("not-a-date")

    assert_redirected_to daily_log_path(Date.current)
    assert_equal "Invalid date format.", flash[:alert]
  end

  test "new entry form succeeds for valid date" do
    date = Date.new(2026, 5, 1)
    get new_log_entry_path(date)

    assert_response :success
  end

  test "edit entry form with invalid date redirects" do
    entry = CalorieEntry.create!(
      eaten_on: Date.new(2026, 5, 2),
      calories: 100,
      meal: :lunch,
      state: :final,
      name: "Wrap"
    )

    get edit_log_calorie_entry_path("bad", entry)

    assert_redirected_to daily_log_path(Date.current)
    assert_equal "Invalid date format.", flash[:alert]
  end

  test "edit entry form succeeds when entry matches date" do
    date = Date.new(2026, 5, 3)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 200,
      meal: :dinner,
      state: :draft,
      name: "Draft item"
    )

    get edit_log_calorie_entry_path(date, entry)

    assert_response :success
  end

  test "show entry with invalid date redirects" do
    entry = CalorieEntry.create!(
      eaten_on: Date.new(2026, 5, 4),
      calories: 150,
      meal: :breakfast,
      state: :final,
      name: "Toast"
    )

    get log_calorie_entry_path("nope", entry)

    assert_redirected_to daily_log_path(Date.current)
    assert_equal "Invalid date format.", flash[:alert]
  end

  test "edit entry redirects when id belongs to another day" do
    day_a = Date.new(2026, 5, 10)
    day_b = Date.new(2026, 5, 11)
    entry = CalorieEntry.create!(
      eaten_on: day_a,
      calories: 300,
      meal: :lunch,
      state: :final,
      name: "Edit wrong day"
    )

    get edit_log_calorie_entry_path(day_b, entry)

    assert_redirected_to daily_log_path(day_b)
    assert_equal "Entry not found for this day.", flash[:alert]
  end

  test "show entry redirects when id belongs to another day" do
    day_a = Date.new(2026, 5, 10)
    day_b = Date.new(2026, 5, 11)
    entry = CalorieEntry.create!(
      eaten_on: day_a,
      calories: 300,
      meal: :lunch,
      state: :final,
      name: "Wrong day probe"
    )

    get log_calorie_entry_path(day_b, entry)

    assert_redirected_to daily_log_path(day_b)
    assert_equal "Entry not found for this day.", flash[:alert]
  end

  test "show returns not found for missing entry id" do
    date = Date.new(2026, 5, 12)
    missing_id = (CalorieEntry.maximum(:id) || 0) + 99_999

    get log_calorie_entry_path(date, missing_id)

    assert_response :not_found
  end

  test "create with invalid date redirects" do
    assert_no_difference("CalorieEntry.count") do
      post log_entries_path(date: "invalid"),
        params: {calorie_entry: {name: "x", meal: "lunch", calories: 100}}
    end

    assert_redirected_to daily_log_path(Date.current)
    assert_equal "Invalid date format.", flash[:alert]
  end

  test "update with invalid date redirects" do
    date = Date.new(2026, 5, 20)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 100,
      meal: :lunch,
      state: :final,
      name: "Keep"
    )

    patch log_entry_path("bad-date", entry),
      params: {calorie_entry: {name: "Keep", meal: "lunch", calories: 100, note: ""}}

    assert_redirected_to daily_log_path(Date.current)
    assert_equal "Invalid date format.", flash[:alert]
    assert_equal "Keep", entry.reload.name
  end

  test "destroy with invalid date redirects" do
    date = Date.new(2026, 5, 21)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 100,
      meal: :lunch,
      state: :final,
      name: "Survives"
    )

    assert_no_difference("CalorieEntry.count") do
      delete delete_log_calorie_entry_path("garbage", entry)
    end

    assert_redirected_to daily_log_path(Date.current)
    assert_equal "Invalid date format.", flash[:alert]
    assert CalorieEntry.exists?(entry.id)
  end

  test "update redirects when entry is not on the requested day" do
    day_a = Date.new(2026, 5, 30)
    day_b = Date.new(2026, 5, 31)
    entry = CalorieEntry.create!(
      eaten_on: day_a,
      calories: 400,
      meal: :dinner,
      state: :final,
      name: "Same"
    )

    patch log_entry_path(day_b, entry),
      params: {calorie_entry: {name: "Changed", meal: "dinner", calories: 400, note: ""}},
      headers: {"Accept" => Mime[:turbo_stream].to_s}

    assert_redirected_to daily_log_path(day_b)
    assert_equal "Entry not found for this day.", flash[:alert]
    assert_equal "Same", entry.reload.name
  end

  test "destroy redirects when entry is not on the requested day" do
    day_a = Date.new(2026, 6, 1)
    day_b = Date.new(2026, 6, 2)
    entry = CalorieEntry.create!(
      eaten_on: day_a,
      calories: 200,
      meal: :lunch,
      state: :final,
      name: "Protected"
    )

    assert_no_difference("CalorieEntry.count") do
      delete delete_log_calorie_entry_path(day_b, entry),
        headers: {"Accept" => Mime[:turbo_stream].to_s}
    end

    assert_redirected_to daily_log_path(day_b)
    assert_equal "Entry not found for this day.", flash[:alert]
    assert CalorieEntry.exists?(entry.id)
  end

  test "create with invalid data renders turbo stream unprocessable" do
    date = Date.new(2026, 6, 10)

    assert_no_difference("CalorieEntry.count") do
      post log_entries_path(date: date),
        params: {
          calorie_entry: {
            name: INVALID_NAME_81,
            meal: "lunch",
            calories: 100
          }
        },
        headers: {"Accept" => Mime[:turbo_stream].to_s}
    end

    assert_response :unprocessable_entity
    assert_equal Mime[:turbo_stream].to_s, response.media_type
  end

  test "create with invalid data redirects html with alert" do
    date = Date.new(2026, 6, 11)

    assert_no_difference("CalorieEntry.count") do
      post log_entries_path(date: date),
        params: {
          calorie_entry: {
            name: INVALID_NAME_81,
            meal: "breakfast",
            calories: 50
          }
        }
    end

    assert_redirected_to daily_log_path(date)
    assert_includes flash[:alert], "Name is too long"
  end

  test "update with invalid data renders turbo stream unprocessable" do
    date = Date.new(2026, 6, 12)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 100,
      meal: :lunch,
      state: :final,
      name: "Valid"
    )

    patch log_entry_path(date, entry),
      params: {
        calorie_entry: {
          name: INVALID_NAME_81,
          meal: "lunch",
          calories: 100,
          note: ""
        }
      },
      headers: {"Accept" => Mime[:turbo_stream].to_s}

    assert_response :unprocessable_entity
    assert_equal "Valid", entry.reload.name
  end

  test "update with invalid data redirects html with alert" do
    date = Date.new(2026, 6, 13)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 120,
      meal: :snack,
      state: :final,
      name: "Ok"
    )

    patch log_entry_path(date, entry),
      params: {
        calorie_entry: {
          name: INVALID_NAME_81,
          meal: "snack",
          calories: 120,
          note: ""
        }
      }

    assert_redirected_to daily_log_path(date)
    assert_includes flash[:alert], "Name is too long"
    assert_equal "Ok", entry.reload.name
  end

  test "destroy html format redirects with notice" do
    date = Date.new(2026, 6, 14)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 90,
      meal: :breakfast,
      state: :final,
      name: "Gone soon"
    )

    assert_difference("CalorieEntry.count", -1) do
      delete delete_log_calorie_entry_path(date, entry)
    end

    assert_redirected_to daily_log_path(date)
    assert_equal "Entry deleted.", flash[:notice]
  end

  test "update html format redirects with notice" do
    date = Date.new(2026, 6, 15)
    entry = CalorieEntry.create!(
      eaten_on: date,
      calories: 250,
      meal: :lunch,
      state: :final,
      name: "Salad"
    )

    patch log_entry_path(date, entry),
      params: {
        calorie_entry: {
          name: "Big salad",
          meal: "lunch",
          calories: 280,
          note: "extra"
        }
      }

    assert_redirected_to daily_log_path(date)
    assert_equal "Entry saved.", flash[:notice]
    entry.reload
    assert_equal "Big salad", entry.name
    assert_equal 280, entry.calories
  end

  test "create html format sets draft notice" do
    date = Date.new(2026, 6, 16)

    assert_difference("CalorieEntry.count", 1) do
      post log_entries_path(date: date),
        params: {
          calorie_entry: {
            name: "Soup",
            meal: "dinner",
            calories: 400,
            note: "pepper"
          }
        }
    end

    assert_redirected_to daily_log_path(date)
    assert_equal "Draft ready - review and save.", flash[:notice]
    assert CalorieEntry.order(:created_at).last.draft?
  end
end
