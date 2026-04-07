# frozen_string_literal: true

# Compares committed eval results against the main-branch baseline and writes
# a markdown report. Optionally checks for stale results when eval-relevant
# code changed without an updated results.yml.
#
# Standalone — no Rails boot required.
#
#   ruby lib/evals/compare_evals.rb [options]
#
# Options:
#   --output=PATH      Write markdown report to PATH (default: stdout)
#   --base-sha=SHA     PR base commit for staleness check (skipped if omitted)

require "optparse"
require "yaml"
require "fileutils"

module CompareEvals
  ROOT = File.expand_path("../../", __dir__)
  RESULTS_PATH = File.join(ROOT, "lib/evals/results.yml")
  RESULTS_GIT_PATH = "lib/evals/results.yml"

  GUARDED_PATHS = %w[
    app/models/food_photo_analyzer.rb
    app/models/meal_suggestion_schema.rb
    config/initializers/ruby_llm.rb
    lib/evals/cases.yml
  ].freeze

  extend self

  def parse_cli!(argv)
    options = {output: nil, base_sha: nil}

    OptionParser.new do |parser|
      parser.banner = "Usage: ruby lib/evals/compare_evals.rb [options]"
      parser.on("--output=PATH", "Write markdown report to PATH (default: stdout)") { |v| options[:output] = v.strip }
      parser.on("--base-sha=SHA", "PR base commit SHA for staleness check") { |v| options[:base_sha] = v.strip }
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
    end.parse!(argv)

    options
  end

  def run!(output: nil, base_sha: nil)
    check_staleness!(base_sha) if base_sha

    current = load_current_results
    baseline = load_baseline_results

    results_changed = current != baseline
    unless results_changed
      warn "results.yml unchanged from baseline — nothing to report."
      return
    end

    report = build_markdown(current, baseline)

    if output
      FileUtils.mkdir_p(File.dirname(output))
      File.write(output, report)
      warn "Report written to #{output}"
    else
      puts report
    end
  end

  private

  # --- staleness check ---

  def check_staleness!(base_sha)
    # check for changes in eval-relevant files
    code_changed = git_diff_names(base_sha, GUARDED_PATHS)
    # check for change in the results.
    results_changed = git_diff_names(base_sha, [RESULTS_GIT_PATH])

    if code_changed.any? && results_changed.empty?
      warn "ERROR: Eval-relevant files changed but results.yml was not updated."
      warn "Changed files: #{code_changed.join(", ")}"
      warn "Run evals locally and commit the updated results.yml."
      exit 1
    end
  end

  def git_diff_names(base_sha, paths)
    cmd = ["git", "diff", "--name-only", base_sha, "HEAD", "--", *paths]
    output = `#{cmd.shelljoin} 2>/dev/null`
    output.split("\n").reject(&:empty?)
  end

  # --- data loading ---

  def load_current_results
    unless File.exist?(RESULTS_PATH)
      warn "No results found at #{RESULTS_PATH}. Run the eval suite first."
      exit 1
    end
    YAML.load_file(RESULTS_PATH, permitted_classes: [Symbol]) || {}
  end

  def load_baseline_results
    yaml = `git show main:#{RESULTS_GIT_PATH} 2>/dev/null`
    if yaml.nil? || yaml.strip.empty?
      warn "No baseline results found at main:#{RESULTS_GIT_PATH}."
      {}
    else
      YAML.load(yaml).transform_keys(&:to_s)
    end
  end

  # --- markdown report ---

  def build_markdown(current, baseline)
    case_ids = (current.keys | baseline.keys).reject { |k| k == "summary" }.sort
    has_baseline = baseline.any?

    lines = []
    lines << "## LLM Eval Results"
    lines << ""
    lines << model_header(current, baseline)
    lines << ""
    lines << case_table(case_ids, current, baseline, has_baseline)
    lines << ""
    lines << summary_section(case_ids, current, baseline, has_baseline)

    lines.join("\n")
  end

  def model_header(current, baseline)
    cur_model = detect_model(current)
    base_model = detect_model(baseline)

    line = "**Model:** #{cur_model || "unknown"}"
    if base_model && cur_model != base_model
      line += " (baseline: #{base_model})"
    end
    line
  end

  def detect_model(results)
    results.each_value do |entry|
      next unless entry.is_a?(Hash)
      model = entry["model_id"]
      return model if model && !model.empty?
    end
    nil
  end

  def case_table(case_ids, current, baseline, has_baseline)
    lines = []

    if has_baseline
      lines << "| Case | Status | Cal. Error | Name Score | Baseline Cal. | Baseline Name | Cal. Delta |"
      lines << "|------|--------|-----------|------------|--------------|--------------|-----------|"
    else
      lines << "| Case | Status | Calorie Error | Name Score |"
      lines << "|------|--------|--------------|------------|"
    end

    case_ids.each do |id|
      cur = current[id] || {}
      base = baseline[id] || {}

      status = cur["success"] ? "✅ Pass" : "❌ **ERROR**"
      cal_err = format_pct(cur["calories_off_percentage"])
      name_sc = format_pct(cur["name_score"])

      if has_baseline
        base_cal = format_pct(base["calories_off_percentage"])
        base_name = format_pct(base["name_score"])
        cal_delta = delta_string(cur["calories_off_percentage"], base["calories_off_percentage"], lower_is_better: true)

        if !cur["success"] && (cur["calories_off_percentage"] > base["calories_off_percentage"] || cur["name_score"] > base["name_score"])
          status = "⚠️ **DEGRADED**"
        end

        lines << "| #{id} | #{status} | #{cal_err} | #{name_sc} | #{base_cal} | #{base_name} | #{cal_delta} |"
      else
        lines << "| #{id} | #{status} | #{cal_err} | #{name_sc} |"
      end
    end

    lines.join("\n")
  end

  def summary_section(case_ids, current, baseline, has_baseline)
    cur_cases = case_ids.filter_map { |id| current[id] }.select { |c| c.is_a?(Hash) && c["success"] }
    base_cases = case_ids.filter_map { |id| baseline[id] }.select { |c| c.is_a?(Hash) && c["success"] }

    cur_cal = avg(cur_cases.filter_map { |c| c["calories_off_percentage"] })
    cur_name = avg(cur_cases.filter_map { |c| c["name_score"] })
    cur_pass = "#{cur_cases.size}/#{case_ids.size}"
    cur_tokens = cur_cases.sum { |c| (c.dig("token_usage", "input") || 0) + (c.dig("token_usage", "output") || 0) }

    lines = []

    if has_baseline
      base_cal = avg(base_cases.filter_map { |c| c["calories_off_percentage"] })
      base_name = avg(base_cases.filter_map { |c| c["name_score"] })
      base_pass = "#{base_cases.size}/#{case_ids.size}"
      base_tokens = base_cases.sum { |c| (c.dig("token_usage", "input") || 0) + (c.dig("token_usage", "output") || 0) }

      lines << "| Metric | Current | Baseline | Delta |"
      lines << "|--------|---------|----------|-------|"
      lines << "| Pass rate | #{cur_pass} | #{base_pass} | |"
      lines << "| Avg calorie error | #{format_pct(cur_cal)} | #{format_pct(base_cal)} | #{delta_string(cur_cal, base_cal, lower_is_better: true)} |"
      lines << "| Avg name score | #{format_pct(cur_name)} | #{format_pct(base_name)} | #{delta_string(cur_name, base_name, lower_is_better: false)} |"
      lines << "| Total tokens | #{cur_tokens} | #{base_tokens} | #{delta_int(cur_tokens, base_tokens)} |"
    else
      lines << "| Metric | Value |"
      lines << "|--------|-------|"
      lines << "| Pass rate | #{cur_pass} |"
      lines << "| Avg calorie error | #{format_pct(cur_cal)} |"
      lines << "| Avg name score | #{format_pct(cur_name)} |"
      lines << "| Total tokens | #{cur_tokens} |"
    end

    lines.join("\n")
  end

  # --- formatting helpers ---

  def avg(values)
    return nil if values.empty?
    values.sum / values.size
  end

  def format_pct(value)
    return "—" if value.nil?

    rounded = value.round(1)
    str = (rounded == rounded.to_i) ? rounded.to_i.to_s : rounded.to_s
    "#{str}%"
  end

  def delta_string(current, baseline, lower_is_better:)
    return "—" if current.nil? || baseline.nil?

    diff = current - baseline
    return "0" if diff.abs < 0.05

    sign = diff.positive? ? "+" : ""
    formatted = "#{sign}#{diff.round(1)}%"

    improved = lower_is_better ? diff.negative? : diff.positive?
    improved ? "#{formatted} :white_check_mark:" : formatted
  end

  def delta_int(current, baseline)
    return "—" if current.nil? || baseline.nil?

    diff = current - baseline
    return "0" if diff.zero?

    sign = diff.positive? ? "+" : ""
    "#{sign}#{diff}"
  end
end

if __FILE__ == $0
  require "shellwords"
  args = CompareEvals.parse_cli!(ARGV)
  CompareEvals.run!(**args)
end
