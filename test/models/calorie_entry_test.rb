require "test_helper"

class CalorieEntryTest < ActiveSupport::TestCase
  test "is valid without an image attachment" do
    entry = CalorieEntry.create!(eaten_on: Date.current, calories: 500, name: "Chicken bowl", meal: :lunch)

    assert_not entry.image.attached?
  end

  test "can attach an optional image" do
    entry = CalorieEntry.create!(eaten_on: Date.current, calories: 650, name: "Steak", meal: :dinner)

    entry.image.attach(
      io: StringIO.new("fake image data"),
      filename: "meal.png",
      content_type: "image/png"
    )

    assert entry.image.attached?
  end

  test "requires eaten_on" do
    entry = CalorieEntry.new(calories: 500)

    assert_not entry.valid?
    assert_includes entry.errors[:eaten_on], "can't be blank"
  end

  test "requires final entries to have integer calories and not be negative" do
    zero_ok = CalorieEntry.new(eaten_on: Date.current, calories: 0, state: :final)
    assert zero_ok.valid?

    negative = CalorieEntry.new(eaten_on: Date.current, calories: -1, state: :final)
    assert_not negative.valid?
    assert_includes negative.errors[:calories], "must be greater than or equal to 0"

    decimal_calorie_entry = CalorieEntry.new(eaten_on: Date.current, calories: 123.5, state: :final)
    assert_not decimal_calorie_entry.valid?
    assert_includes decimal_calorie_entry.errors[:calories], "must be an integer"
  end

  test "for_day returns entries for one day only" do
    today_entry = CalorieEntry.create!(eaten_on: Date.current, calories: 600, name: "Sandwich", meal: :lunch)
    CalorieEntry.create!(eaten_on: Date.current - 1, calories: 400, name: "Soup", meal: :dinner)

    assert_equal [today_entry.id], CalorieEntry.for_day(Date.current).pluck(:id)
  end

  test "between returns entries in inclusive date range" do
    older_entry = CalorieEntry.create!(eaten_on: Date.current - 10, calories: 350, name: "Bar", meal: :snack)
    start_range_entry = CalorieEntry.create!(eaten_on: Date.current - 3, calories: 500, name: "Oatmeal", meal: :breakfast)
    end_range_entry = CalorieEntry.create!(eaten_on: Date.current, calories: 800, name: "Pasta", meal: :dinner)

    results = CalorieEntry.between(Date.current - 3, Date.current).pluck(:id)

    assert_equal [start_range_entry.id, end_range_entry.id].sort, results.sort
    assert_not_includes results, older_entry.id
  end

  test "supports meal enum classification" do
    entry = CalorieEntry.create!(eaten_on: Date.current, calories: 420, meal: :snack)

    assert entry.snack?
    assert_includes CalorieEntry.snack, entry
  end

  test "finalized scope excludes draft entries" do
    final = CalorieEntry.create!(eaten_on: Date.current, calories: 300, meal: :lunch, state: :final)
    draft = CalorieEntry.create!(eaten_on: Date.current, calories: 1, meal: :other, state: :draft, name: "Draft only")

    assert_includes CalorieEntry.finalized, final
    assert_not_includes CalorieEntry.finalized, draft
  end

  test "draft entries skip calories validation for final-only rule when not final" do
    entry = CalorieEntry.new(eaten_on: Date.current, calories: 1, meal: :other, state: :draft)

    assert entry.valid?
  end

  test "cannot revert from final to draft" do
    entry = CalorieEntry.create!(eaten_on: Date.current, calories: 200, meal: :dinner, state: :final)

    entry.state = :draft
    assert_not entry.valid?
    assert_includes entry.errors[:state], "cannot change from final to draft"
  end

  test "merge_ai_metadata merges string keys" do
    entry = CalorieEntry.new(eaten_on: Date.current, calories: 100, meal: :breakfast, state: :final)
    entry.merge_ai_metadata!("analysis_status" => "skipped")
    entry.merge_ai_metadata!("user_description" => "hello")

    assert_equal "skipped", entry.ai_metadata["analysis_status"]
    assert_equal "hello", entry.ai_metadata["user_description"]
  end
end
