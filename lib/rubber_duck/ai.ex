defmodule RubberDuck.AI do
  @moduledoc """
  Domain for AI-related resources in RubberDuck.
  
  Manages analysis results from AI services and user-created prompts
  for various AI operations.
  """

  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.AI.AnalysisResult do
      define :create_analysis_result, action: :create
      define :get_analysis_result, action: :read, get_by: [:id]
      define :list_analysis_results, action: :read
      define :list_analysis_results_by_project, action: :by_project, args: [:project_id]
      define :list_analysis_results_by_code_file, action: :by_code_file, args: [:code_file_id]
      define :list_analysis_results_by_type, action: :by_analysis_type, args: [:analysis_type]
      define :list_completed_analysis_results, action: :completed
      define :update_analysis_result, action: :update
      define :delete_analysis_result, action: :destroy
    end

    resource RubberDuck.AI.Prompt do
      define :create_prompt, action: :create
      define :get_prompt, action: :read, get_by: [:id]
      define :list_prompts, action: :read
      define :list_prompts_by_author, action: :by_author
      define :list_public_prompts, action: :public
      define :list_prompts_by_category, action: :by_category, args: [:category]
      define :list_prompts_by_tag, action: :by_tag, args: [:tag]
      define :search_prompts, action: :search, args: [:search_term]
      define :update_prompt, action: :update
      define :increment_prompt_usage, action: :increment_usage
      define :delete_prompt, action: :destroy
    end
  end
end