# frozen_string_literal: true

class PromptEvaluation::RunResult
  attr_reader :eval_case, :llm_result, :runtime

  def initialize(eval_case:, llm_result:, runtime:)
    @eval_case = eval_case
    @llm_result = llm_result
    @runtime = runtime
  end

  def success? = llm_result.success

  def actual_calories = llm_result.attributes&.calories
  def actual_name = llm_result.attributes&.name

  # --- scoring ---

  def calories_off_percentage
    return nil if actual_calories.blank?

    ((actual_calories - eval_case.expected_calories).abs / eval_case.expected_calories.to_f) * 100
  end
  alias_method :calorie_score, :calories_off_percentage

  def name_score
    return nil if actual_name.blank?

    expected_words = eval_case.expected_name.downcase.split(" ")
    matched_count = expected_words.count { |word| actual_name.downcase.include?(word) }
    (matched_count / expected_words.count.to_f) * 100
  end

  # --- output ---

  def to_lines
    return failure_lines unless success?

    lines = ["[#{eval_case.id}] ✓"]
    lines << "Runtime   #{runtime} seconds" if runtime.present?
    lines << token_usage_line if token_usage?
    lines << calorie_detail_line if calories_off_percentage.present?
    lines << name_detail_line if name_score.present?
    lines
  end

  def to_persistable_hash
    {
      success: success?,
      runtime: runtime,
      token_usage: llm_result.token_usage&.stringify_keys,
      calories_off_percentage: calories_off_percentage,
      name_score: name_score
    }.stringify_keys
  end

  private

  def failure_lines
    msg = llm_result.error_message.to_s.strip.gsub(/\s+/, " ")
    ["[#{eval_case.id}] ✗", msg.presence || "(no error message)"]
  end

  def calorie_detail_line
    "Calories  #{actual_calories}  (expected #{eval_case.expected_calories})  —  #{format_pct(calories_off_percentage)}% off"
  end

  def name_detail_line
    "Name      #{actual_name.inspect}  (expected #{eval_case.expected_name.inspect})  —  #{format_pct(name_score)}% words matched"
  end

  def token_usage?
    usage = llm_result.token_usage
    usage.present? && (usage[:input].positive? || usage[:output].positive?)
  end

  def token_usage_line
    usage = llm_result.token_usage
    "Tokens    #{usage[:input]} (input) + #{usage[:output]} (output) = #{usage[:input] + usage[:output]} (total)"
  end

  def format_pct(value)
    return "—" if value.nil?

    rounded = value.round(1)
    (rounded == rounded.to_i) ? rounded.to_i.to_s : rounded.to_s
  end
end
