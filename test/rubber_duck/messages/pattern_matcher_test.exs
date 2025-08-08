defmodule RubberDuck.Messages.PatternMatcherTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Messages.PatternMatcher
  
  describe "matches?/2" do
    test "exact match without wildcards" do
      assert PatternMatcher.matches?("code.analyze.file", "code.analyze.file")
      refute PatternMatcher.matches?("code.analyze.file", "code.quality.check")
    end
    
    test "single wildcard at the end" do
      assert PatternMatcher.matches?("code.analyze.file", "code.analyze.*")
      assert PatternMatcher.matches?("code.analyze.directory", "code.analyze.*")
      refute PatternMatcher.matches?("code.quality.check", "code.analyze.*")
    end
    
    test "wildcard in the middle" do
      assert PatternMatcher.matches?("code.analyze.file", "code.*.file")
      assert PatternMatcher.matches?("code.quality.file", "code.*.file")
      refute PatternMatcher.matches?("code.analyze.directory", "code.*.file")
    end
    
    test "wildcard at the beginning" do
      assert PatternMatcher.matches?("code.analyze.file", "*.analyze.file")
      assert PatternMatcher.matches?("system.analyze.file", "*.analyze.file")
      refute PatternMatcher.matches?("code.quality.check", "*.analyze.file")
    end
    
    test "multiple wildcards" do
      assert PatternMatcher.matches?("code.analyze.file", "*.*.file")
      assert PatternMatcher.matches?("system.process.file", "*.*.file")
      refute PatternMatcher.matches?("code.analyze.directory", "*.*.file")
    end
    
    test "single wildcard matches everything" do
      assert PatternMatcher.matches?("code.analyze.file", "*")
      assert PatternMatcher.matches?("anything.at.all", "*")
    end
    
    test "wildcard at higher level" do
      assert PatternMatcher.matches?("code.analyze.file", "code.*")
      assert PatternMatcher.matches?("code.quality.check", "code.*")
      assert PatternMatcher.matches?("code.security.scan.deep", "code.*")
      refute PatternMatcher.matches?("project.analyze.file", "code.*")
    end
  end
  
  describe "find_matching_patterns/2" do
    test "returns all matching patterns sorted by specificity" do
      patterns = [
        "code.*",
        "code.analyze.*",
        "code.analyze.file",
        "*.analyze.*",
        "*"
      ]
      
      result = PatternMatcher.find_matching_patterns("code.analyze.file", patterns)
      
      # Most specific (no wildcards) should come first
      # Note: code.* and *.analyze.* both have same wildcard count but code.* has more concrete segments
      assert result == [
        "code.analyze.file",  # No wildcards, exact match
        "code.analyze.*",     # One wildcard, most specific prefix
        "code.*",             # One wildcard, less specific prefix
        "*",                  # One wildcard, no prefix (least specific single wildcard)
        "*.analyze.*"         # Two wildcards (least specific overall)
      ]
    end
    
    test "returns empty list when no patterns match" do
      patterns = ["project.*", "user.*", "system.*"]
      result = PatternMatcher.find_matching_patterns("code.analyze.file", patterns)
      assert result == []
    end
  end
  
  describe "find_best_match/2" do
    test "returns the most specific matching pattern" do
      patterns = ["code.*", "code.analyze.*", "*.analyze.*", "*"]
      
      assert PatternMatcher.find_best_match("code.analyze.file", patterns) == "code.analyze.*"
    end
    
    test "returns nil when no pattern matches" do
      patterns = ["project.*", "user.*"]
      
      assert PatternMatcher.find_best_match("code.analyze.file", patterns) == nil
    end
  end
  
  describe "expand_pattern/2" do
    test "returns all signal types matching a wildcard pattern" do
      signal_types = [
        "code.analyze.file",
        "code.analyze.directory",
        "code.quality.check",
        "code.security.scan",
        "project.analyze.structure"
      ]
      
      result = PatternMatcher.expand_pattern("code.analyze.*", signal_types)
      
      assert Enum.sort(result) == [
        "code.analyze.directory",
        "code.analyze.file"
      ]
    end
    
    test "returns empty list for non-matching pattern" do
      signal_types = ["code.analyze.file", "code.quality.check"]
      
      result = PatternMatcher.expand_pattern("project.*", signal_types)
      
      assert result == []
    end
  end
  
  describe "has_wildcard?/1" do
    test "detects patterns with wildcards" do
      assert PatternMatcher.has_wildcard?("code.*")
      assert PatternMatcher.has_wildcard?("*.analyze.*")
      assert PatternMatcher.has_wildcard?("*")
      
      refute PatternMatcher.has_wildcard?("code.analyze.file")
      refute PatternMatcher.has_wildcard?("project.structure.analyze")
    end
  end
  
  describe "base_pattern/1" do
    test "extracts pattern prefix before first wildcard" do
      assert PatternMatcher.base_pattern("code.analyze.*") == "code.analyze"
      assert PatternMatcher.base_pattern("code.*") == "code"
      assert PatternMatcher.base_pattern("*.analyze.*") == ""
      assert PatternMatcher.base_pattern("*") == ""
      assert PatternMatcher.base_pattern("code.analyze.file") == "code.analyze.file"
    end
  end
end