defmodule RubberDuck.Messages.Registry do
  @moduledoc """
  Central registry for all message types and their routing information.
  
  Provides bidirectional mapping between string-based signal patterns
  and strongly-typed message modules for backward compatibility with Jido.
  
  ## Usage
  
      # Look up message type from string pattern
      Registry.lookup_type("code.analyze.file")
      #=> RubberDuck.Messages.Code.Analyze
      
      # Get string pattern for message type
      Registry.pattern_for_type(RubberDuck.Messages.Code.Analyze)
      #=> "code.analyze.file"
      
      # Get all registered types
      Registry.all_types()
      #=> [RubberDuck.Messages.Code.Analyze, ...]
  """
  
  @type_mappings %{
    # Code analysis messages
    "code.analyze.file" => RubberDuck.Messages.Code.Analyze,
    "code.quality.check" => RubberDuck.Messages.Code.QualityCheck,
    "code.impact.assess" => RubberDuck.Messages.Code.ImpactAssess,
    "code.performance.analyze" => RubberDuck.Messages.Code.PerformanceAnalyze,
    "code.security.scan" => RubberDuck.Messages.Code.SecurityScan,
    
    # Learning messages
    "learning.experience.record" => RubberDuck.Messages.Learning.RecordExperience,
    "learning.feedback.process" => RubberDuck.Messages.Learning.ProcessFeedback,
    "learning.pattern.analyze" => RubberDuck.Messages.Learning.AnalyzePattern,
    "learning.optimize.agent" => RubberDuck.Messages.Learning.OptimizeAgent,
    "learning.share.knowledge" => RubberDuck.Messages.Learning.ShareKnowledge,
    "learning.experience.query" => RubberDuck.Messages.Learning.QueryExperience,
    
    # Project messages
    "project.quality.monitor" => RubberDuck.Messages.Project.MonitorQuality,
    "project.optimization.suggest" => RubberDuck.Messages.Project.SuggestOptimization,
    "project.structure.analyze" => RubberDuck.Messages.Project.AnalyzeStructure,
    "project.dependency.detect" => RubberDuck.Messages.Project.DetectDependencies,
    
    # User messages
    "user.session.manage" => RubberDuck.Messages.User.ManageSession,
    "user.behavior.learn" => RubberDuck.Messages.User.LearnBehavior,
    "user.preference.update" => RubberDuck.Messages.User.UpdatePreference
  }
  
  # Create reverse mapping at compile time for performance
  @reverse_mappings Map.new(@type_mappings, fn {pattern, module} -> {module, pattern} end)
  
  @doc """
  Looks up the message type module for a given string pattern.
  
  Returns the module if found, nil otherwise.
  """
  @spec lookup_type(String.t()) :: module() | nil
  def lookup_type(string_pattern) when is_binary(string_pattern) do
    Map.get(@type_mappings, string_pattern)
  end
  
  @doc """
  Gets the string pattern for a given message type module.
  
  Returns the pattern if found, nil otherwise.
  """
  @spec pattern_for_type(module()) :: String.t() | nil
  def pattern_for_type(module) when is_atom(module) do
    Map.get(@reverse_mappings, module)
  end
  
  @doc """
  Returns all registered message type modules.
  """
  @spec all_types() :: [module()]
  def all_types do
    Map.values(@type_mappings)
  end
  
  @doc """
  Returns all registered string patterns.
  """
  @spec all_patterns() :: [String.t()]
  def all_patterns do
    Map.keys(@type_mappings)
  end
  
  @doc """
  Checks if a string pattern is registered.
  """
  @spec pattern_registered?(String.t()) :: boolean()
  def pattern_registered?(pattern) when is_binary(pattern) do
    Map.has_key?(@type_mappings, pattern)
  end
  
  @doc """
  Checks if a message type module is registered.
  """
  @spec type_registered?(module()) :: boolean()
  def type_registered?(module) when is_atom(module) do
    Map.has_key?(@reverse_mappings, module)
  end
  
  @doc """
  Groups patterns by their domain (first part of the pattern).
  
  ## Example
  
      Registry.patterns_by_domain()
      #=> %{
        "code" => ["code.analyze.file", "code.quality.check", ...],
        "learning" => ["learning.experience.record", ...],
        ...
      }
  """
  @spec patterns_by_domain() :: %{String.t() => [String.t()]}
  def patterns_by_domain do
    @type_mappings
    |> Map.keys()
    |> Enum.group_by(&extract_domain/1)
  end
  
  @doc """
  Groups message types by their domain.
  """
  @spec types_by_domain() :: %{String.t() => [module()]}
  def types_by_domain do
    @type_mappings
    |> Enum.group_by(fn {pattern, _module} -> extract_domain(pattern) end)
    |> Map.new(fn {domain, pairs} ->
      {domain, Enum.map(pairs, fn {_pattern, module} -> module end)}
    end)
  end
  
  defp extract_domain(pattern) do
    pattern
    |> String.split(".")
    |> List.first()
  end
end