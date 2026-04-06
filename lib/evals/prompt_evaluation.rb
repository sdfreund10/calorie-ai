require "optparse"
require "yaml"

# IDEA: Store some results in a committed file.
#   A CI worker pulls that file from the main branch and compares if to a new run on the current branch.
#   Then the branch can update the results file and reset the baseline in the main automatically.
module PromptEvaluation
  extend self

  def parse_cli!(argv)
    options = {
      model_id: RubyLLM.config.default_model,
      save_results: true,
      only_case_id: nil
    }

    OptionParser.new do |parser|
      script = Pathname.new(__FILE__).relative_path_from(Rails.root)
      parser.banner = <<~BANNER
        Run FoodPhotoAnalyzer against eval cases in lib/evals/cases.yml.

        Usage:
          bin/rails runner #{script} [options]

        Examples:
          bin/rails runner #{script} --case-id=grilled_chicken_breast
          bin/rails runner #{script} --model=gpt-4o-mini --no-save
      BANNER

      parser.separator ""
      parser.separator "Options:"

      parser.on("--model=ID", "RubyLLM model id (default: #{RubyLLM.config.default_model})") { |v| options[:model_id] = v.strip }
      parser.on("--no-save", "Do not write lib/evals/results.yml") { options[:save_results] = false }
      parser.on("--case-id=ID", "Run only this case id") { |v| options[:only_case_id] = v.strip }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
    end.parse!(argv)

    options
  end

  # runs evaluation, prints result, and optionally persists metrics to lib/evals/results.yml
  def run!(model_id: RubyLLM.config.default_model, save_results: true, only_case_id: nil)
    start_message = "Running evaluations with model #{model_id}."
    start_message += " --no-save" unless save_results
    start_message += " --case-id=#{only_case_id}" if only_case_id
    puts start_message
    all_cases = Case.all
    cases = only_case_id ? all_cases.select { |c| c.id == only_case_id } : all_cases
    if only_case_id && cases.empty?
      warn "Unknown --case-id=#{only_case_id}. Valid ids: #{all_cases.map(&:id).join(", ")}"
      exit 1
    end

    puts "Running #{cases.count} cases#{" (model: #{model_id})" if model_id.present?}..."

    puts "Results:"
    cases.each do |test_case|
      test_case.run!(model_id: model_id)
      lines = test_case.result_lines
      puts "  #{lines.first}"
      lines.drop(1).each { |line| puts "    #{line}" }
      test_case.save_result! if save_results
      # TODO: Run test cases multiple times and average the results
      # 2.times do
      #   test_case.rerun!
      #   lines = test_case.result_lines
      #   puts "  #{lines.first}"
      #   lines.drop(1).each { |line| puts "    #{line}" }
      # end
    end
  end

  class Case
    attr_reader :id

    def initialize(id:, image_url:, source_url:, user_description:, expectations:)
      @id = id
      @image_url = image_url
      @source_url = source_url
      @user_description = user_description
      @expectations = expectations.with_indifferent_access
      @runtime = nil
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

    def with_timing
      start = Time.now
      result = yield
      @runtime = Time.now - start
      result
    end

    def run!(model_id: RubyLLM.config.default_model)
      @llm_result ||= with_remote_image do |image_path|
        with_timing do
          FoodPhotoAnalyzer.new(image_path: image_path, user_description: @user_description, model_id: model_id).call
        end
      end
    end

    def rerun!
      @llm_result = nil
      run!
    end

    attr_reader :llm_result

    def save_result!
      file = Rails.root.join("lib", "evals", "results.yml")
      results = YAML.load_file(file) || {}
      results[@id] = {
        success: success?,
        runtime: @runtime,
        token_usage: llm_result.token_usage&.stringify_keys,
        calories_off_percentage: calories_off_percentage,
        name_score: name_score
      }.stringify_keys
      File.write(file, results.to_yaml)
    end

    def expected_calories
      @expectations[:calories]
    end

    # One line per logical row; first row is the case header, rest are details (indented when printed).
    def result_lines
      return failure_result_lines unless success?

      lines = ["[#{@id}] ✓"]
      lines << runtime_line if @runtime.present?
      lines << token_usage_string if token_usage_line?
      lines << calorie_detail_line if calories_off_percentage.present?
      lines << name_detail_line if name_score.present?
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

    def name_score
      return nil if result_name.blank?

      expected_words = expectation_name.split(" ")
      matched_word_count = expected_words.count { |word| result_name.include?(word) }
      (matched_word_count / expected_words.count.to_f) * 100
    end

    def self.all
      file = Rails.root.join("lib", "evals", "cases.yml")
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

    def result_name
      llm_result.attributes&.name
    end

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

    def runtime_line
      "Runtime   #{@runtime} seconds"
    end

    def format_pct(value)
      return "—" if value.nil?

      rounded = value.round(1)
      return rounded.to_i.to_s if rounded == rounded.to_i

      rounded.to_s
    end
  end
end

if __FILE__ == $0
  args = PromptEvaluation.parse_cli!(ARGV)
  PromptEvaluation.run!(**args)
end
