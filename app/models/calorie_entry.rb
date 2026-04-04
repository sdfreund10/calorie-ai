# frozen_string_literal: true

class CalorieEntry < ApplicationRecord
  MAX_IMAGE_BYTES = 15.megabytes
  ALLOWED_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

  has_one_attached :image

  enum :meal, {breakfast: 0, lunch: 1, dinner: 2, snack: 3, other: 4}
  enum :state, {draft: 0, final: 1}, default: :draft

  validates :eaten_on, presence: true
  validates :calories, presence: true, numericality: {only_integer: true, greater_than_or_equal_to: 0}, if: :final?
  validates :name, length: {maximum: 80}, allow_blank: true
  validate :image_type_and_size, if: -> { image.attached? }
  validate :no_revert_from_final_to_draft

  scope :for_day, ->(date) { where(eaten_on: date) }
  scope :between, ->(start_date, end_date) { where(eaten_on: start_date..end_date) }
  scope :finalized, -> { where(state: :final) }

  store_accessor :ai_metadata, :analysis_status, :error_message, :suggestions, :model
  before_create :set_defaults

  def analyze!
    return unless image.attached? && draft?

    analysis = image.blob.open do |file|
      FoodPhotoAnalyzer.new(
        image_path: file.path,
        user_description: note
      ).call
    end

    if analysis.success
      self.analysis_status = "completed"
      self.suggestions = analysis.attributes.to_h
      self.error_message = nil
      self.name = analysis.attributes.name
      self.calories = analysis.attributes.calories
      if analysis.attributes.note.present?
        ai_suffix = "✨ AI Analysis ✨\n#{analysis.attributes.note}"
        self.note = note.present? ? "#{note}\n#{ai_suffix}" : ai_suffix
      end
    else
      self.analysis_status = "failed"
      self.error_message = analysis.error_message
    end
    save!
  end

  private

  def set_defaults
    self.state ||= :draft
    self.calories ||= 0
  end

  def no_revert_from_final_to_draft
    return unless persisted? && state_in_database == "final" && draft?

    errors.add(:state, "cannot change from final to draft")
  end

  def image_type_and_size
    return if image.blob.blank?

    unless ALLOWED_IMAGE_TYPES.include?(image.blob.content_type)
      errors.add(:image, "must be JPEG, PNG, GIF, or WebP")
    end
    if image.blob.byte_size > MAX_IMAGE_BYTES
      errors.add(:image, "is too large (max #{MAX_IMAGE_BYTES / 1.megabyte} MB)")
    end
  end
end
