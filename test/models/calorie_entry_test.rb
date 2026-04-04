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

  test "requires calories to be a positive integer" do
    zero_calorie_entry = CalorieEntry.new(eaten_on: Date.current, calories: 0)
    decimal_calorie_entry = CalorieEntry.new(eaten_on: Date.current, calories: 123.5)

    assert_not zero_calorie_entry.valid?
    assert_includes zero_calorie_entry.errors[:calories], "must be greater than 0"

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
end
