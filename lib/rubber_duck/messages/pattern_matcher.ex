defmodule RubberDuck.Messages.PatternMatcher do
  @moduledoc """
  Provides pattern matching capabilities for signal types with wildcard support.

  Supports Jido-style wildcard patterns where "*" matches any sequence of characters
  at that position in the signal type hierarchy.

  ## Examples

      iex> PatternMatcher.matches?("code.analyze.file", "code.analyze.*")
      true
      
      iex> PatternMatcher.matches?("code.analyze.file", "code.*")
      true
      
      iex> PatternMatcher.matches?("code.analyze.file", "*.analyze.*")
      true
      
      iex> PatternMatcher.matches?("code.quality.check", "code.analyze.*")
      false
  """

  @doc """
  Checks if a signal type matches a pattern with wildcards.

  Patterns can contain "*" which matches any sequence of characters
  up to the next dot or end of string.
  """
  @spec matches?(String.t(), String.t()) :: boolean()
  def matches?(signal_type, pattern) when is_binary(signal_type) and is_binary(pattern) do
    pattern_regex = pattern_to_regex(pattern)
    Regex.match?(pattern_regex, signal_type)
  end

  @doc """
  Finds all patterns that match a given signal type from a list of patterns.

  Returns a list of matching patterns, sorted by specificity (most specific first).
  """
  @spec find_matching_patterns(String.t(), [String.t()]) :: [String.t()]
  def find_matching_patterns(signal_type, patterns) when is_list(patterns) do
    patterns
    |> Enum.filter(&matches?(signal_type, &1))
    |> sort_by_specificity()
  end

  @doc """
  Finds the most specific pattern that matches a signal type.

  Returns nil if no pattern matches.
  """
  @spec find_best_match(String.t(), [String.t()]) :: String.t() | nil
  def find_best_match(signal_type, patterns) do
    case find_matching_patterns(signal_type, patterns) do
      [best | _] -> best
      [] -> nil
    end
  end

  @doc """
  Expands a wildcard pattern to match all registered signal types.

  Returns a list of concrete signal types that match the pattern.
  """
  @spec expand_pattern(String.t(), [String.t()]) :: [String.t()]
  def expand_pattern(pattern, signal_types) when is_list(signal_types) do
    Enum.filter(signal_types, &matches?(&1, pattern))
  end

  @doc """
  Checks if a pattern contains wildcards.
  """
  @spec has_wildcard?(String.t()) :: boolean()
  def has_wildcard?(pattern) do
    String.contains?(pattern, "*")
  end

  @doc """
  Extracts the base pattern without wildcards.

  ## Examples

      iex> PatternMatcher.base_pattern("code.analyze.*")
      "code.analyze"
      
      iex> PatternMatcher.base_pattern("code.*")
      "code"
  """
  @spec base_pattern(String.t()) :: String.t()
  def base_pattern(pattern) do
    pattern
    |> String.split(".")
    |> Enum.take_while(&(&1 != "*"))
    |> Enum.join(".")
  end

  # Private functions

  defp pattern_to_regex(pattern) do
    # Escape special regex characters except for our wildcard
    escaped =
      pattern
      |> String.replace(".", "\\.")
      |> String.replace("*", ".*")

    # Anchor the pattern to match the entire string
    ~r/^#{escaped}$/
  end

  defp sort_by_specificity(patterns) do
    # More specific patterns (fewer wildcards, more segments) come first
    Enum.sort_by(patterns, fn pattern ->
      wildcard_count = pattern |> String.graphemes() |> Enum.count(&(&1 == "*"))
      segment_count = pattern |> String.split(".") |> length()

      non_wildcard_segments =
        pattern |> String.split(".") |> Enum.reject(&(&1 == "*")) |> length()

      # Return tuple for sorting: 
      # 1. Fewer wildcards = higher priority
      # 2. More non-wildcard segments = higher priority  
      # 3. More total segments = higher priority
      {wildcard_count, -non_wildcard_segments, -segment_count}
    end)
  end
end
