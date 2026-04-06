require "optparse"
require "yaml"

# IDEA: Store some results in a committed file.
#   A CI worker pulls that file from the main branch and compares if to a new run on the current branch.
#   Then the branch can update the results file and reset the baseline in the main automatically.
module PromptEvaluation
  extend self

  require_relative "prompt_evaluation/case"
  require_relative "prompt_evaluation/run_result"
  require_relative "prompt_evaluation/runner"

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
end

if __FILE__ == $0
  args = PromptEvaluation.parse_cli!(ARGV)
  PromptEvaluation::Runner.new(**args).call
end
