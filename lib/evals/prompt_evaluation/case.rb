# frozen_string_literal: true

class PromptEvaluation::Case
  CASES_PATH = Rails.root.join("lib/evals/cases.yml")

  attr_reader :id, :image_url, :source_url, :user_description, :expectations

  def initialize(id:, image_url:, source_url:, user_description:, expectations:)
    @id = id
    @image_url = image_url
    @source_url = source_url
    @user_description = user_description
    @expectations = expectations.with_indifferent_access
  end

  def expected_calories = expectations[:calories]
  def expected_name = expectations[:name]

  def self.all
    YAML.load_file(CASES_PATH)["cases"].map { |data| new(**data.symbolize_keys) }
  end
end
