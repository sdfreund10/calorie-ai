# frozen_string_literal: true

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
    draft = CalorieEntry.new(eaten_on: Date.current, calories: -1, state: :draft)
    assert draft.valid?
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

  test "set_defaults assigns draft state and zero calories when omitted on create" do
    entry = CalorieEntry.new(eaten_on: Date.current, meal: :lunch)
    entry.save!

    assert entry.draft?
    assert_equal 0, entry.calories
  end

  test "set_defaults does not override explicit state and calories" do
    entry = CalorieEntry.create!(
      eaten_on: Date.current,
      meal: :breakfast,
      state: :final,
      calories: 250,
      name: "Eggs"
    )

    assert entry.final?
    assert_equal 250, entry.calories
  end

  test "rejects disallowed image content types" do
    entry = CalorieEntry.new(eaten_on: Date.current, meal: :lunch, calories: 100)
    entry.image.attach(
      io: StringIO.new("%PDF-1.4"),
      filename: "doc.pdf",
      content_type: "application/pdf"
    )

    assert_not entry.valid?
    assert_includes entry.errors[:image], "must be JPEG, PNG, GIF, or WebP"
  end

  test "rejects images over the max byte size" do
    original_max = CalorieEntry::MAX_IMAGE_BYTES
    CalorieEntry.send(:remove_const, :MAX_IMAGE_BYTES)
    CalorieEntry.const_set(:MAX_IMAGE_BYTES, 80)

    entry = CalorieEntry.new(eaten_on: Date.current, meal: :lunch, calories: 100)
    entry.image.attach(
      io: StringIO.new("x" * 81),
      filename: "big.png",
      content_type: "image/png"
    )

    assert_not entry.valid?
    assert_match(/too large/i, entry.errors[:image].join)
  ensure
    CalorieEntry.send(:remove_const, :MAX_IMAGE_BYTES)
    CalorieEntry.const_set(:MAX_IMAGE_BYTES, original_max)
  end

  test "rejects name longer than 80 characters" do
    entry = CalorieEntry.new(
      eaten_on: Date.current,
      meal: :lunch,
      calories: 100,
      state: :final,
      name: "a" * 81
    )

    assert_not entry.valid?
    assert_includes entry.errors[:name], "is too long (maximum is 80 characters)"
  end

  test "analyze! is a no-op without an attached image" do
    refute_food_photo_analyzer_called("FoodPhotoAnalyzer should not run without an image") do
      entry = CalorieEntry.create!(eaten_on: Date.current, meal: :lunch, calories: 10, state: :draft)
      entry.analyze!

      entry.reload
      assert_nil entry.analysis_status
    end
  end

  test "analyze! is a no-op when entry is not draft" do
    refute_food_photo_analyzer_called("FoodPhotoAnalyzer should not run for non-draft entries") do
      entry = CalorieEntry.create!(eaten_on: Date.current, meal: :lunch, calories: 300, state: :final, name: "Final meal")
      entry.image.attach(
        io: StringIO.new("fake"),
        filename: "m.png",
        content_type: "image/png"
      )
      entry.analyze!

      entry.reload
      assert_nil entry.analysis_status
    end
  end

  test "analyze! applies successful analyzer output and persists" do
    stub_food_photo_analyzer_call(
      content: {name: "AI Chili", calories: 480, note: "rough guess"},
      model: "gpt-test"
    ) do
      entry = CalorieEntry.create!(
        eaten_on: Date.current,
        meal: :lunch,
        calories: 0,
        state: :draft,
        note: "User context"
      )
      entry.image.attach(
        io: StringIO.new("fake-bytes"),
        filename: "meal.png",
        content_type: "image/png"
      )

      entry.analyze!
      entry.reload

      assert_equal "completed", entry.analysis_status
      assert_nil entry.error_message
      assert_equal "AI Chili", entry.name
      assert_equal 480, entry.calories
      assert_equal "User context\n✨ AI Analysis ✨\nrough guess", entry.note
      assert_equal(
        {"name" => "AI Chili", "calories" => 480, "note" => "rough guess"},
        entry.suggestions
      )
    end
  end

  test "analyze! appends AI note when entry note was blank" do
    stub_food_photo_analyzer_call(
      content: {name: "Soup", calories: 200, note: "light"},
      model: "m"
    ) do
      entry = CalorieEntry.create!(eaten_on: Date.current, meal: :dinner, calories: 0, state: :draft, note: nil)
      entry.image.attach(io: StringIO.new("x"), filename: "m.png", content_type: "image/png")

      entry.analyze!

      assert_equal "✨ AI Analysis ✨\nlight", entry.reload.note
    end
  end

  test "analyze! records failure when analyzer does not succeed" do
    stub_food_photo_analyzer_call(
      success: false,
      error_message: "Vision API unavailable."
    ) do
      entry = CalorieEntry.create!(eaten_on: Date.current, meal: :other, calories: 0, state: :draft)
      entry.image.attach(io: StringIO.new("x"), filename: "m.png", content_type: "image/png")

      entry.analyze!

      entry.reload
      assert_equal "failed", entry.analysis_status
      assert_equal "Vision API unavailable.", entry.error_message
    end
  end
end
