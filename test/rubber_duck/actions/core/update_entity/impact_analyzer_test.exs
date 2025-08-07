defmodule RubberDuck.Actions.Core.UpdateEntity.ImpactAnalyzerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Actions.Core.UpdateEntity.ImpactAnalyzer
  
  describe "analyze/2" do
    setup do
      entity = %{
        id: "test-123",
        type: :user,
        email: "user@example.com",
        username: "testuser",
        role: :member
      }
      
      validated_changes = %{
        changes: %{username: "newusername", role: :admin},
        change_count: 2,
        change_severity: :medium,
        validations: %{
          field_validation: %{valid: true},
          constraint_validation: %{valid: true}
        }
      }
      
      {:ok, entity: entity, changes: validated_changes}
    end
    
    test "performs comprehensive impact analysis", %{entity: entity, changes: changes} do
      params = %{entity: entity, validated_changes: changes}
      
      assert {:ok, result} = ImpactAnalyzer.analyze(params, %{})
      assert result.impact_score >= 0 and result.impact_score <= 1
      assert is_map(result.impact_details)
      assert is_list(result.recommendations)
      assert is_list(result.mitigation_strategies)
    end
    
    test "includes all impact dimensions", %{entity: entity, changes: changes} do
      params = %{entity: entity, validated_changes: changes}
      
      {:ok, result} = ImpactAnalyzer.analyze(params, %{})
      impact = result.impact_details
      
      assert Map.has_key?(impact, :direct_impact)
      assert Map.has_key?(impact, :dependency_impact)
      assert Map.has_key?(impact, :performance_impact)
      assert Map.has_key?(impact, :system_impact)
      assert Map.has_key?(impact, :risk_assessment)
      assert Map.has_key?(impact, :affected_entities)
      assert Map.has_key?(impact, :propagation_analysis)
    end
    
    test "identifies rollback points", %{entity: entity, changes: changes} do
      params = %{entity: entity, validated_changes: changes}
      
      {:ok, result} = ImpactAnalyzer.analyze(params, %{})
      
      assert is_list(result.rollback_points)
      assert Enum.all?(result.rollback_points, fn {point, requirement} ->
        is_atom(point) and is_atom(requirement)
      end)
    end
  end
  
  describe "analyze_direct_impact/2" do
    test "calculates direct impact metrics" do
      entity = %{type: :user}
      changes = %{
        changes: %{name: "new", age: 26},
        change_severity: :low,
        validations: %{
          field_validation: %{valid: true},
          constraint_validation: %{valid: true}
        }
      }
      
      result = ImpactAnalyzer.analyze_direct_impact(entity, changes)
      
      assert result.fields_affected == 2
      assert result.severity == :low
      assert is_list(result.immediate_effects)
      assert result.data_integrity_impact == :minimal
      assert result.validation_score == 1.0
    end
    
    test "handles missing validations gracefully" do
      entity = %{type: :user}
      changes = %{changes: %{name: "new"}, change_severity: :high}
      
      result = ImpactAnalyzer.analyze_direct_impact(entity, changes)
      
      assert result.fields_affected == 1
      assert result.severity == :high
      assert result.validation_score == 1.0
    end
  end
  
  describe "analyze_dependency_impact/2" do
    test "identifies dependencies for user entity" do
      entity = %{type: :user, id: "user-123"}
      changes = %{changes: %{email: "new@example.com"}}
      
      result = ImpactAnalyzer.analyze_dependency_impact(entity, changes)
      
      assert result.dependent_count > 0
      assert :sessions in Enum.map(result.cascade_effects, & &1.dependency)
      assert is_list(result.critical_dependencies)
      assert is_map(result.dependency_graph)
    end
    
    test "identifies breaking changes" do
      entity = %{type: :code_file}
      changes = %{changes: %{path: "/new/path.ex"}}
      
      result = ImpactAnalyzer.analyze_dependency_impact(entity, changes)
      
      assert {:path_change, :affects_imports} in result.breaking_changes
    end
    
    test "builds dependency graph" do
      entity = %{type: :project, id: "proj-123"}
      changes = %{changes: %{status: :archived}}
      
      result = ImpactAnalyzer.analyze_dependency_impact(entity, changes)
      
      assert result.dependency_graph.root == "proj-123"
      assert :code_files in result.dependency_graph.nodes
      assert {:project, :code_files} in result.dependency_graph.edges
    end
  end
  
  describe "estimate_performance_impact/2" do
    test "estimates latency for small changes" do
      entity = %{type: :user}
      changes = %{changes: %{name: "short"}}
      
      result = ImpactAnalyzer.estimate_performance_impact(entity, changes)
      
      assert result.expected_latency_change == "< 1ms"
      assert result.memory_impact == "negligible"
      assert result.throughput_impact == "no impact"
    end
    
    test "estimates latency for large changes" do
      entity = %{type: :code_file}
      large_content = String.duplicate("x", 50_000)
      changes = %{changes: %{content: large_content}}
      
      result = ImpactAnalyzer.estimate_performance_impact(entity, changes)
      
      assert result.expected_latency_change in ["10-100ms", "> 100ms"]
      assert result.memory_impact in ["10-100KB", "100KB-1MB"]
    end
    
    test "identifies optimization opportunities" do
      entity = %{type: :project}
      changes = %{
        changes: Enum.into(1..15, %{}, fn i -> {"field_#{i}", "value_#{i}"} end)
      }
      
      result = ImpactAnalyzer.estimate_performance_impact(entity, changes)
      
      assert :batch_processing in result.optimization_opportunities
    end
  end
  
  describe "assess_system_wide_impact/2" do
    test "determines cache invalidation requirements" do
      entity = %{type: :user}
      changes = %{changes: %{preferences: %{theme: "dark"}}}
      
      result = ImpactAnalyzer.assess_system_wide_impact(entity, changes)
      
      assert result.cache_invalidation_required == true
    end
    
    test "identifies index update needs" do
      entity = %{type: :user}
      changes = %{changes: %{email: "new@example.com"}}
      
      result = ImpactAnalyzer.assess_system_wide_impact(entity, changes)
      
      assert result.index_updates_needed == true
    end
    
    test "determines notification scope" do
      entity = %{type: :project}
      changes = %{change_severity: :high}
      
      result = ImpactAnalyzer.assess_system_wide_impact(entity, changes)
      
      assert result.notification_scope == :team
    end
    
    test "assesses audit impact" do
      entity = %{type: :user}
      changes = %{changes: %{role: :admin}, change_severity: :critical}
      
      result = ImpactAnalyzer.assess_system_wide_impact(entity, changes)
      
      assert result.audit_trail_impact.audit_required == true
      assert result.audit_trail_impact.audit_level == :detailed
      assert result.audit_trail_impact.retention_period == :permanent
    end
  end
  
  describe "assess_update_risks/2" do
    test "identifies data loss risk" do
      entity = %{type: :user}
      changes = %{changes: %{bio: ""}}
      
      result = ImpactAnalyzer.assess_update_risks(entity, changes)
      
      assert {:data_loss, :high} in result.identified_risks
      assert result.mitigation_required == true
    end
    
    test "identifies consistency risk" do
      entity = %{type: :user}
      changes = %{changes: %{email: "new@example.com"}}
      
      result = ImpactAnalyzer.assess_update_risks(entity, changes)
      
      assert {:consistency, :medium} in result.identified_risks
    end
    
    test "identifies performance risk" do
      entity = %{type: :code_file}
      large_changes = %{
        changes: %{content: String.duplicate("x", 200_000)}
      }
      
      result = ImpactAnalyzer.assess_update_risks(entity, large_changes)
      
      assert {:performance, :medium} in result.identified_risks
    end
    
    test "calculates overall risk level" do
      entity = %{type: :user}
      changes = %{changes: %{password_hash: "new_hash"}}
      
      result = ImpactAnalyzer.assess_update_risks(entity, changes)
      
      assert {:security, :critical} in result.identified_risks
      assert result.risk_level == :critical
    end
    
    test "builds risk matrix" do
      entity = %{type: :user}
      changes = %{changes: %{email: "", password_hash: "hash"}}
      
      result = ImpactAnalyzer.assess_update_risks(entity, changes)
      
      assert is_map(result.risk_matrix.by_type)
      assert is_map(result.risk_matrix.by_level)
    end
  end
  
  describe "identify_affected_entities/2" do
    test "identifies affected entities for user" do
      entity = %{type: :user, id: "user-123"}
      changes = %{}
      
      result = ImpactAnalyzer.identify_affected_entities(entity, changes)
      
      assert {:sessions, "user-123", :invalidate} in result
      assert {:preferences, "user-123", :update} in result
    end
    
    test "identifies affected entities for project" do
      entity = %{type: :project, id: "proj-123"}
      changes = %{}
      
      result = ImpactAnalyzer.identify_affected_entities(entity, changes)
      
      assert {:code_files, "proj-123", :revalidate} in result
      assert {:analyses, "proj-123", :recompute} in result
      assert {:deployments, "proj-123", :check} in result
    end
  end
  
  describe "analyze_propagation_requirements/2" do
    test "determines propagation is needed for critical changes" do
      entity = %{type: :project}
      changes = %{change_severity: :critical}
      
      result = ImpactAnalyzer.analyze_propagation_requirements(entity, changes)
      
      assert result.propagation_needed == true
      assert result.propagation_strategy == :immediate
      assert result.propagation_timeout == 5_000
    end
    
    test "determines propagation order" do
      entity = %{type: :user}
      changes = %{change_severity: :high}
      
      result = ImpactAnalyzer.analyze_propagation_requirements(entity, changes)
      
      assert result.propagation_order == [:sessions, :preferences, :projects]
    end
  end
  
  describe "calculate_overall_impact_score/1" do
    test "calculates weighted score from all dimensions" do
      impact = %{
        direct_impact: %{
          fields_affected: 5,
          severity: :medium,
          validation_score: 1.0
        },
        dependency_impact: %{
          dependent_count: 3,
          critical_dependencies: [:sessions],
          breaking_changes: []
        },
        performance_impact: %{
          expected_latency_change: "1-10ms"
        },
        system_impact: %{
          cache_invalidation_required: true,
          index_updates_needed: false,
          notification_scope: :team
        },
        risk_assessment: %{
          risk_level: :medium
        }
      }
      
      score = ImpactAnalyzer.calculate_overall_impact_score(impact)
      
      assert score >= 0 and score <= 1
      assert is_float(score)
    end
  end
  
  describe "generate_impact_recommendations/1" do
    test "generates recommendations based on impact" do
      impact = %{
        direct_impact: %{fields_affected: 15},
        dependency_impact: %{critical_dependencies: [:sessions]},
        performance_impact: %{expected_latency_change: "> 100ms"},
        risk_assessment: %{mitigation_required: true}
      }
      
      recommendations = ImpactAnalyzer.generate_impact_recommendations(impact)
      
      assert "Consider batching changes" in recommendations
      assert "Monitor critical dependencies during update" in recommendations
      assert "Consider async processing" in recommendations
      assert "Implement rollback strategy" in recommendations
    end
  end
  
  describe "suggest_mitigation_strategies/1" do
    test "suggests strategies for critical risk" do
      impact = %{
        risk_assessment: %{risk_level: :critical},
        performance_impact: %{resource_usage_change: "minimal"},
        system_impact: %{cache_invalidation_required: false}
      }
      
      strategies = ImpactAnalyzer.suggest_mitigation_strategies(impact)
      
      assert "Create backup before update" in strategies
      assert "Prepare rollback plan" in strategies
    end
    
    test "suggests performance mitigation" do
      impact = %{
        risk_assessment: %{risk_level: :low},
        performance_impact: %{resource_usage_change: "significant"},
        system_impact: %{cache_invalidation_required: true}
      }
      
      strategies = ImpactAnalyzer.suggest_mitigation_strategies(impact)
      
      assert "Scale resources temporarily" in strategies
      assert "Implement rate limiting" in strategies
      assert "Warm cache after update" in strategies
    end
  end
  
  describe "identify_rollback_points/1" do
    test "identifies rollback points based on impact" do
      impact = %{
        direct_impact: %{fields_affected: 5},
        dependency_impact: %{breaking_changes: [{:api_change, :breaking}]},
        system_impact: %{index_updates_needed: true}
      }
      
      points = ImpactAnalyzer.identify_rollback_points(impact)
      
      assert {:before_field_updates, :snapshot_required} in points
      assert {:before_dependency_updates, :dependency_snapshot} in points
      assert {:before_index_updates, :index_backup} in points
    end
  end
end