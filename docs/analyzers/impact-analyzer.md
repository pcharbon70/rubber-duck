# Impact Analyzer

## Overview

The Impact Analyzer (`RubberDuck.Analyzers.Code.Impact`) assesses the potential impact of code changes on the broader system. It evaluates scope, dependency effects, risk factors, and provides guidance for change management.

## Analysis Capabilities

### 1. Change Impact Assessment

#### Scope Analysis
- **Local**: Changes isolated to single function/module
- **Module**: Changes affecting entire module
- **Package**: Changes affecting multiple modules
- **System**: Changes with system-wide implications

#### Severity Levels
- **Low**: Minor changes with minimal risk
- **Medium**: Moderate changes requiring review
- **High**: Significant changes requiring careful testing
- **Critical**: Changes requiring extensive validation

### 2. Dependency Impact Analysis

#### Direct Dependencies
- Modules that directly import/use the changed code
- Functions that call modified functions
- Immediate callers and consumers

#### Transitive Dependencies
- Indirect dependencies through the call graph
- Modules affected by cascading changes
- Potential ripple effects

#### Dependency Metrics
```elixir
%{
  direct_dependencies: 8,           # Direct importers
  transitive_dependencies: 45,      # Total affected modules
  dependency_depth: 4,              # Maximum call chain depth
  critical_path_length: 12          # Longest dependency chain
}
```

### 3. Risk Assessment

#### Risk Factors
- **API Changes**: Breaking vs non-breaking changes
- **Core Module Changes**: Changes to foundational modules
- **Public Interface Changes**: External API modifications
- **Data Structure Changes**: Schema or format modifications

#### Risk Calculation
```elixir
risk_score = (
  breaking_changes * 0.4 +
  core_module_factor * 0.3 +
  dependency_count_factor * 0.2 +
  complexity_factor * 0.1
)
```

### 4. Change Complexity Analysis

#### Complexity Indicators
- Number of lines changed
- Number of functions modified
- Structural changes (new/removed functions)
- Breaking vs non-breaking changes

## Usage

### Direct Analysis

```elixir
alias RubberDuck.Analyzers.Code.Impact
alias RubberDuck.Messages.Code.ImpactAssess

# Assess change impact
message = %ImpactAssess{
  file_path: "/lib/user_service.ex",
  changes: %{
    lines_added: 25,
    lines_removed: 10,
    functions_added: ["create_admin_user/2"],
    functions_modified: ["authenticate/2", "authorize/3"],
    functions_removed: [],
    breaking_changes: true,
    api_changes: true
  },
  context: %{
    git_diff: diff_content,
    previous_analysis: previous_result,
    deployment_target: :production
  }
}

{:ok, result} = Impact.analyze(message, %{state: app_state})

# Result structure
%{
  scope: :extensive,                 # :local, :module, :package, :extensive
  severity: :high,                   # :low, :medium, :high, :critical
  
  dependency_impact: %{
    direct_dependencies: 12,
    transitive_dependencies: 67,
    affected_modules: [
      "UserController",
      "AuthService", 
      "SessionManager",
      "AdminPanel"
    ],
    critical_dependencies: [
      "AuthService"              # High-risk dependencies
    ]
  },
  
  risk_assessment: %{
    level: :high,                # Overall risk level
    score: 7.2,                  # Risk score (0-10)
    factors: [
      "Breaking API changes detected",
      "Core authentication module modified",
      "12+ direct dependencies affected",
      "Production deployment target"
    ],
    mitigation_strategies: [
      "Implement feature flags",
      "Deploy to staging first",
      "Create rollback plan"
    ]
  },
  
  change_analysis: %{
    type: :feature_enhancement,   # :bugfix, :feature, :refactor, :breaking
    complexity: :moderate,        # Based on lines/functions changed
    estimated_effort: :significant, # :trivial, :minor, :moderate, :significant, :major
    rollback_complexity: :complex   # How difficult to undo
  },
  
  recommendations: [
    %{
      type: :testing,
      priority: :high,
      action: "Add comprehensive integration tests",
      details: "Focus on authentication flow and admin user creation"
    },
    %{
      type: :deployment,
      priority: :high, 
      action: "Use feature flags for gradual rollout",
      details: "Enable admin user creation incrementally"
    }
  ],
  
  timeline_estimate: %{
    development: "2-3 days",
    testing: "1-2 days", 
    deployment: "1 day",
    total: "4-6 days"
  }
}
```

### Via Comprehensive Analysis

```elixir
alias RubberDuck.Messages.Code.Analyze

message = %Analyze{
  file_path: "/lib/critical_service.ex",
  analysis_type: :impact,
  depth: :deep
}

{:ok, result} = CodeAnalysisSkill.handle_analyze(message, context)
```

## Impact Assessment Examples

### Low Impact Change

```elixir
# Minor bug fix
changes = %{
  lines_added: 2,
  lines_removed: 1,
  functions_modified: ["format_date/1"],
  breaking_changes: false,
  api_changes: false
}

# Result
%{
  scope: :local,
  severity: :low,
  risk_assessment: %{
    level: :low,
    score: 1.5,
    factors: ["Internal function change", "No API impact"]
  },
  estimated_effort: :trivial,
  rollback_complexity: :simple
}
```

### High Impact Change

```elixir
# Database schema migration
changes = %{
  lines_added: 150,
  lines_removed: 75,
  functions_modified: ["create_user/1", "update_user/2", "get_user/1"],
  functions_added: ["migrate_user_data/0"],
  breaking_changes: true,
  api_changes: true,
  schema_changes: true
}

# Result  
%{
  scope: :extensive,
  severity: :critical,
  dependency_impact: %{
    direct_dependencies: 25,
    transitive_dependencies: 89,
    affected_modules: ["UserController", "AuthService", "ProfileService", ...]
  },
  risk_assessment: %{
    level: :critical,
    score: 9.1,
    factors: [
      "Database schema changes",
      "Breaking API changes",
      "25+ direct dependencies",
      "Core user model affected"
    ]
  },
  estimated_effort: :major,
  rollback_complexity: :very_complex
}
```

## Risk Level Interpretation

### Risk Score Scale (0-10)

- **0-2**: Minimal risk, safe to deploy
- **2-4**: Low risk, standard review process
- **4-6**: Moderate risk, additional testing recommended
- **6-8**: High risk, extensive testing required
- **8-10**: Critical risk, phased deployment essential

### Risk Factors

#### Breaking Changes (+3.0)
- API signature changes
- Removed public functions
- Changed return types

#### Core Module Changes (+2.0)
- Authentication/authorization
- Database access layers
- Configuration systems

#### High Dependency Count (+1.5)
- 10+ direct dependencies: +1.0
- 20+ direct dependencies: +1.5
- 50+ transitive dependencies: +2.0

#### Complexity Factors (+1.0)
- Large line count changes (>100 lines): +0.5
- Multiple function modifications: +0.5
- Structural changes: +0.5

## Dependency Analysis

### Dependency Graph Analysis

```elixir
%{
  dependency_graph: %{
    "UserService" => %{
      direct_dependents: ["UserController", "AuthService"],
      transitive_dependents: ["SessionManager", "AdminPanel", ...],
      dependency_depth: 3,
      criticality: :high
    }
  },
  
  impact_propagation: %{
    immediate: ["UserController"],          # 1 hop
    secondary: ["AuthService", "Profile"],  # 2 hops  
    tertiary: ["AdminPanel", "Reports"]     # 3+ hops
  },
  
  bottleneck_analysis: %{
    critical_paths: [
      ["UserService", "AuthService", "SessionManager"],
      ["UserService", "UserController", "Router"]
    ],
    single_points_of_failure: ["UserService"]
  }
}
```

### Module Criticality Assessment

```elixir
module_criticality = %{
  "UserService" => %{
    criticality: :critical,
    reasons: [
      "Core authentication dependency",
      "25+ modules depend on it", 
      "No alternative implementations"
    ],
    blast_radius: :system_wide
  },
  
  "ReportGenerator" => %{
    criticality: :low,
    reasons: [
      "Isolated functionality",
      "2 modules depend on it",
      "Non-critical business logic"
    ],
    blast_radius: :local
  }
}
```

## Change Management Recommendations

### Deployment Strategies

#### Low Risk Changes
```elixir
%{
  strategy: :direct_deployment,
  steps: [
    "Run automated tests",
    "Deploy to production", 
    "Monitor for 15 minutes"
  ],
  rollback_plan: "Simple git revert"
}
```

#### High Risk Changes
```elixir
%{
  strategy: :phased_deployment,
  steps: [
    "Deploy to staging environment",
    "Run comprehensive integration tests",
    "Deploy with feature flags disabled",
    "Enable for 5% of users",
    "Monitor metrics for 24 hours",
    "Gradually increase to 100%"
  ],
  rollback_plan: "Disable feature flags, revert if necessary",
  monitoring: [
    "Error rates",
    "Response times", 
    "User authentication success rate"
  ]
}
```

### Testing Recommendations

#### Impact-Based Testing Strategy

```elixir
testing_strategy = %{
  unit_tests: %{
    priority: :high,
    focus: "Modified functions and their direct callers",
    coverage_target: 0.95
  },
  
  integration_tests: %{
    priority: :critical,
    focus: "End-to-end workflows affected by changes",
    scenarios: [
      "User login flow",
      "Admin user creation",
      "Session management"
    ]
  },
  
  contract_tests: %{
    priority: :high,
    focus: "API contracts for breaking changes",
    validations: ["Request/response schemas", "Error handling"]
  },
  
  performance_tests: %{
    priority: :medium,
    focus: "Changed code paths under load",
    benchmarks: ["Authentication latency", "Database query performance"]
  }
}
```

## Configuration Options

```elixir
impact_config = %{
  # Risk calculation weights
  risk_weights: %{
    breaking_changes: 0.4,
    core_module_factor: 0.3,
    dependency_count: 0.2,
    complexity: 0.1
  },
  
  # Dependency analysis settings
  dependency_analysis: %{
    max_depth: 5,              # Maximum dependency traversal depth
    include_test_deps: false,  # Include test-only dependencies
    critical_modules: [        # Modules with extra impact weight
      "Auth", "Database", "Config"
    ]
  },
  
  # Scope thresholds
  scope_thresholds: %{
    local: %{max_dependencies: 2, max_lines: 20},
    module: %{max_dependencies: 10, max_lines: 100},
    package: %{max_dependencies: 25, max_lines: 500},
    extensive: %{max_dependencies: 999, max_lines: 999}
  },
  
  # Risk level thresholds
  risk_thresholds: %{
    low: 2.0,
    medium: 4.0,
    high: 6.0,
    critical: 8.0
  }
}
```

## Integration Examples

### Pre-deployment Check

```elixir
defmodule DeploymentGate do
  alias RubberDuck.Analyzers.Code.Impact
  
  def check_deployment_readiness(changed_files, deployment_env) do
    results = Enum.map(changed_files, fn file ->
      message = %ImpactAssess{
        file_path: file.path,
        changes: extract_changes(file),
        context: %{deployment_target: deployment_env}
      }
      
      Impact.analyze(message, %{})
    end)
    
    aggregate_risk = calculate_aggregate_risk(results)
    
    case aggregate_risk.level do
      level when level in [:low, :medium] ->
        {:ok, "Deployment approved"}
        
      :high ->
        {:warning, "High risk deployment - additional approval required"}
        
      :critical ->
        {:error, "Critical risk deployment - blocked"}
    end
  end
end
```

### Change Review Assistant

```elixir
defmodule ChangeReviewer do
  def generate_review_checklist(impact_result) do
    base_checklist = [
      "Code review completed",
      "Unit tests passing",
      "Documentation updated"
    ]
    
    impact_checklist = case impact_result.severity do
      :low -> []
      :medium -> [
        "Integration tests reviewed",
        "Stakeholder notification sent"
      ]
      :high -> [
        "Full regression testing completed",
        "Rollback plan documented", 
        "Performance impact assessed"
      ]
      :critical -> [
        "Architecture review completed",
        "Security review completed",
        "Deployment runbook created",
        "Monitoring alerts configured",
        "Phased rollout plan approved"
      ]
    end
    
    base_checklist ++ impact_checklist
  end
end
```

## Limitations

1. **Static Analysis**: Cannot predict runtime behavior changes
2. **Dependency Discovery**: May miss dynamic dependencies
3. **Context Awareness**: Limited understanding of business logic
4. **Historical Data**: Requires change history for better predictions

## Future Enhancements

1. **Machine Learning**: Learn from historical change outcomes
2. **Runtime Dependencies**: Integrate with application telemetry
3. **Business Impact**: Correlate technical changes with business metrics
4. **Automated Testing**: Generate test cases based on impact analysis
5. **Deployment Automation**: Integrate with CI/CD pipelines
6. **Real-time Monitoring**: Track actual impact post-deployment
7. **Team Collaboration**: Integration with project management tools

## Best Practices

### For Development Teams

1. **Run Impact Analysis Early**: Before starting implementation
2. **Use Results for Planning**: Factor impact into sprint planning
3. **Document High-Impact Changes**: Create detailed change documentation
4. **Plan Rollback Strategies**: Always have an exit plan

### For Release Management

1. **Gate Deployments**: Use risk scores to gate production deployments
2. **Schedule High-Risk Changes**: Plan critical changes during low-traffic periods
3. **Coordinate Teams**: Notify affected teams before high-impact deployments
4. **Monitor Post-Deployment**: Track actual vs predicted impact

### For Code Reviews

1. **Focus Review Effort**: Spend more time on high-impact changes
2. **Expand Reviewer Pool**: Include stakeholders for critical changes
3. **Test Strategy Review**: Validate testing approach matches impact level
4. **Documentation Requirements**: Require docs for significant changes