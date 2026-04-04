class CalorieEntry < ApplicationRecord
  has_one_attached :image

  enum :meal, { breakfast: 0, lunch: 1, dinner: 2, snack: 3, other: 4 }

  validates :eaten_on, presence: true
  validates :calories, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :name, length: { maximum: 80 }, allow_blank: true

  scope :for_day, ->(date) { where(eaten_on: date) }
  scope :between, ->(start_date, end_date) { where(eaten_on: start_date..end_date) }
end
