require "yaml"

# TODO: Log values for comparison over time
# TODO: More test cases
# TODO: Run test cases multiple times and average the results
# TODO: Estimate token usage and cost of tests
# TODO: Introduce variants (ie no description)
# TODO: Log time taken for each test case
module PromptEvaluation
  extend self

  # Invoked from the bottom of this file when executed via `rails runner lib/prompt_evaluation.rb`.
  # The file can load twice in one process (Zeitwerk/autoload_lib during boot, then Kernel.load from
  # runner); without this guard, `run!` would fire twice.
  def self.run_from_cli!
    return unless __FILE__ == $0
    return if @cli_runner_done

    @cli_runner_done = true
    run!
  end

  # runs evaluation, prints result, and logs to file
  def self.run!
    cases = Case.all
    puts "Running #{cases.count} cases..."

    puts "Results:"
    cases.each do |test_case|
      test_case.run!
      lines = test_case.result_lines
      puts "  #{lines.first}"
      lines.drop(1).each { |line| puts "    #{line}" }
      # 2.times do
      #   test_case.rerun!
      #   lines = test_case.result_lines
      #   puts "  #{lines.first}"
      #   lines.drop(1).each { |line| puts "    #{line}" }
      # end
    end
  end

  class Case
    def initialize(id:, image_url:, source_url:, user_description:, expectations:)
      @id = id
      @image_url = image_url
      @source_url = source_url
      @user_description = user_description
      @expectations = expectations.with_indifferent_access
    end

    def with_remote_image(&block)
      # download file and save to temp file
      Tempfile.create(["prompt_evaluation_image_#{@id}", ".jpg"]) do |file|
        file.binmode
        file.write(URI.parse(@image_url).read)
        file.rewind
        yield file.path
      end
    end

    def run!
      @llm_result ||= with_remote_image do |image_path|
        FoodPhotoAnalyzer.new(image_path: image_path, user_description: @user_description).call
      end
    end

    def rerun!
      @llm_result = nil
      run!
    end

    attr_reader :llm_result

    def expected_calories
      @expectations[:calories]
    end

    # One line per logical row; first row is the case header, rest are details (indented when printed).
    def result_lines
      return failure_result_lines unless success?

      lines = ["[#{@id}] ✓"]
      lines << calorie_detail_line if calories_off_percentage.present?
      lines << name_detail_line if name_score.present?
      lines << token_usage_string if token_usage_line?
      lines
    end

    def result_string
      result_lines.join("\n")
    end

    def success?
      llm_result.success
    end

    def actual_calories
      llm_result.attributes&.calories
    end

    def calories_off
      return nil if actual_calories.blank?

      (actual_calories - expected_calories).abs
    end

    def calories_off_percentage
      return nil if calories_off.blank?

      (calories_off / expected_calories.to_f) * 100
    end
    alias_method :calorie_score, :calories_off_percentage

    def expectation_name
      @expectations[:name]
    end

    def result_name
      llm_result.attributes&.name
    end

    def name_score
      return nil if result_name.blank?

      expected_words = expectation_name.split(" ")
      matched_word_count = expected_words.count { |word| result_name.include?(word) }
      (matched_word_count / expected_words.count.to_f) * 100
    end

    def self.all
      file = Rails.root.join("lib", "prompt_evaluation", "cases.yml")
      YAML.load_file(file)["cases"].map do |case_data|
        new(
          id: case_data["id"],
          image_url: case_data["image_url"],
          source_url: case_data["source_url"],
          user_description: case_data["user_description"],
          expectations: case_data["expectations"]
        )
      end
    end

    private

    def failure_result_lines
      msg = llm_result.error_message.to_s.strip.gsub(/\s+/, " ")
      ["[#{@id}] ✗", msg.presence || "(no error message)"]
    end

    def calorie_detail_line
      pct = format_pct(calories_off_percentage)
      "Calories  #{actual_calories}  (expected #{expected_calories})  —  #{pct}% off"
    end

    def name_detail_line
      pct = format_pct(name_score)
      "Name      #{result_name.inspect}  (expected #{expectation_name.inspect})  —  #{pct}% words matched"
    end

    def token_usage_line?
      usage = llm_result.token_usage
      usage.present? && (usage[:input].positive? || usage[:output].positive?)
    end

    def token_usage_string
      usage = llm_result.token_usage
      "Tokens    #{usage[:input]} (input) + #{usage[:output]} (output) = #{usage[:input] + usage[:output]} (total)"
    end

    def format_pct(value)
      return "—" if value.nil?

      rounded = value.round(1)
      return rounded.to_i.to_s if rounded == rounded.to_i

      rounded.to_s
    end
  end
end

PromptEvaluation.run_from_cli!
