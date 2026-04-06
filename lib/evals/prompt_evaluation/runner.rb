# frozen_string_literal: true

class PromptEvaluation::Runner
  RESULTS_PATH = Rails.root.join("lib/evals/results.yml")

  def initialize(model_id: RubyLLM.config.default_model, save_results: true, only_case_id: nil)
    @model_id = model_id
    @save_results = save_results
    @only_case_id = only_case_id
  end

  def call
    print_header
    cases = resolve_cases

    results = cases.map do |eval_case|
      result = run_case(eval_case)
      print_result(result)
      save_result!(result) if @save_results
      result
    end

    print_summary(results)
  end

  private

  def resolve_cases
    all_cases = PromptEvaluation::Case.all

    return all_cases if @only_case_id.nil?

    filtered = all_cases.select { |c| c.id == @only_case_id }
    if filtered.empty?
      warn "Unknown --case-id=#{@only_case_id}. Valid ids: #{all_cases.map(&:id).join(", ")}"
      exit 1
    end
    filtered
  end

  def run_case(eval_case)
    with_remote_image(eval_case) do |image_path|
      runtime, llm_result = with_timing do
        FoodPhotoAnalyzer.new(image_path: image_path, user_description: eval_case.user_description, model_id: @model_id).call
      end
      PromptEvaluation::RunResult.new(eval_case: eval_case, llm_result: llm_result, runtime: runtime)
    end
  end

  def with_remote_image(eval_case)
    Tempfile.create(["prompt_evaluation_image_#{eval_case.id}", ".jpg"]) do |file|
      file.binmode
      file.write(URI.parse(eval_case.image_url).read)
      file.rewind
      yield file.path
    end
  end

  def with_timing
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    [elapsed, result]
  end

  # --- output ---

  def print_header
    parts = ["Running evaluations with model #{@model_id}."]
    parts << " --no-save" unless @save_results
    parts << " --case-id=#{@only_case_id}" if @only_case_id
    puts parts.join
  end

  def print_result(result)
    lines = result.to_lines
    puts "  #{lines.first}"
    lines.drop(1).each { |line| puts "    #{line}" }
  end

  def print_summary(results)
    puts "\nSummary (#{results.size} cases):"

    successes = results.select(&:success?)
    puts "  Pass rate:          #{successes.size}/#{results.size}"

    calorie_scores = successes.filter_map(&:calories_off_percentage)
    if calorie_scores.any?
      avg = calorie_scores.sum / calorie_scores.size
      puts "  Avg calorie error:  #{avg.round(1)}%"
    end

    name_scores = successes.filter_map(&:name_score)
    if name_scores.any?
      avg = name_scores.sum / name_scores.size
      puts "  Avg name score:     #{avg.round(1)}%"
    end

    total_tokens = successes.sum { |r| r.llm_result.token_usage&.values_at(:input, :output)&.compact&.sum || 0 }
    puts "  Total tokens:       #{total_tokens}" if total_tokens.positive?

    total_runtime = results.sum(&:runtime)
    puts "  Total runtime:      #{total_runtime.round(2)}s"

    if @save_results
      results = YAML.load_file(RESULTS_PATH) || {}
      results["summary"] = {
        pass_rate: successes.size / results.size,
        avg_calorie_error: calorie_scores.sum / calorie_scores.size,
        avg_name_score: name_scores.sum / name_scores.size,
        total_tokens: total_tokens,
        total_runtime: total_runtime
      }
      File.write(RESULTS_PATH, results.to_yaml)
    end
  end

  # --- persistence ---

  def save_result!(result)
    results = YAML.load_file(RESULTS_PATH) || {}
    results[result.eval_case.id] = result.to_persistable_hash
    File.write(RESULTS_PATH, results.to_yaml)
  end
end
