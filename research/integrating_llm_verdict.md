# Integrating Verdict-based LLM judges into rubber-duck

This comprehensive guide provides a detailed implementation strategy for integrating an LLM-as-a-judge system based on the Verdict research paper into the rubber-duck Elixir-based agentic coding assistant. While the specific planning documents were not accessible, this research synthesizes best practices from the Verdict framework, Elixir ecosystem patterns, and industry standards for code quality evaluation.

## Verdict framework offers modular, scalable judge architecture

The Verdict paper introduces a paradigm shift in LLM-as-a-judge systems through **judge-time compute scaling** rather than simply using larger models. The framework achieves state-of-the-art results by composing modular reasoning units (verification, debate, aggregation) into sophisticated evaluation pipelines. For code quality assessment, Verdict's key innovations include hierarchical verification patterns that combine initial judgment with verification layers, ensemble voting for reliability, and progressive enhancement strategies that balance cost with evaluation depth. The framework specifically addresses common judge reliability issues like position bias, length bias, and inconsistent scoring through systematic mitigation strategies.

Verdict's modular unit system provides several specialized components particularly suited for code evaluation. The **JudgeUnit** handles standard evaluations with configurable scales, the **PairwiseJudgeUnit** enables comparative code assessment, and the **CategoricalJudgeUnit** classifies code quality aspects. These units can be composed using layers and pipelines to create sophisticated evaluation workflows. For instance, a judge-then-verify pattern first evaluates code quality, then validates that assessment through a separate verification unit, significantly improving reliability while maintaining cost efficiency through selective use of more expensive models only when needed.

The framework's emphasis on token efficiency makes it particularly attractive for production systems. By implementing progressive evaluation strategies—starting with lightweight screening using cheaper models like GPT-4o-mini, then selectively applying detailed analysis with GPT-4o only when necessary—organizations can achieve 60-80% cost reduction compared to uniform deep analysis. Verdict's built-in rate limiting, concurrent execution capabilities, and intelligent retry strategies ensure robust operation at scale.

## Elixir ecosystem provides robust foundation for judge integration

The combination of Elixir's concurrency model, the Ash framework's declarative resource management, and Jido's multi-agent orchestration capabilities creates an ideal environment for implementing LLM judges. Ash resources can model evaluations as first-class domain entities with built-in validation and state machine support through AshStateMachine, enabling sophisticated evaluation lifecycle management. The framework's action system naturally accommodates complex evaluation workflows with automatic error handling and retry logic.

Jido's agent-based architecture aligns perfectly with Verdict's modular approach. Each Verdict unit can be implemented as a Jido.Agent with clear responsibilities, while Jido.Workflow manages the overall evaluation pipeline. The library's sensor capabilities enable real-time monitoring of judge performance, token usage, and evaluation quality metrics. This architecture naturally supports horizontal scaling through Elixir's lightweight process model and OTP supervision trees.

For HTTP integration with LLM APIs, Finch provides optimal performance through connection pooling and HTTP/2 support, essential for high-throughput evaluation scenarios. Combined with circuit breaker patterns using libraries like Fuse, the system can gracefully handle API failures and rate limits. Broadway and GenStage offer powerful primitives for batch processing evaluations with back-pressure control, enabling efficient handling of large-scale code review operations while respecting API rate limits and budget constraints.

## Architecture design balances modularity with performance

The recommended architecture implements a three-layer design that separates concerns while maintaining high cohesion. The **Domain Layer** uses Ash resources to model code evaluations, quality metrics, and feedback entities with full audit trails. The **Orchestration Layer** leverages Jido agents to coordinate evaluation workflows, implementing Verdict's modular units as autonomous agents that can be composed into complex pipelines. The **Infrastructure Layer** handles API integration, caching, and monitoring through GenServer processes and OTP supervision trees.

```elixir
defmodule RubberDuck.CodeQuality.Judge do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer
  
  attributes do
    uuid_primary_key :id
    attribute :code_snippet, :text, allow_nil?: false
    attribute :evaluation_type, :atom, constraints: [one_of: [:quality, :security, :performance]]
    attribute :score, :integer, constraints: [min: 1, max: 5]
    attribute :explanation, :text
    attribute :token_cost, :integer
    attribute :model_used, :string
    timestamps()
  end
  
  actions do
    defaults [:create, :read, :update]
    
    action :evaluate, :update do
      accept [:code_snippet, :evaluation_type]
      change RubberDuck.CodeQuality.Changes.RunEvaluation
    end
  end
end

defmodule RubberDuck.CodeQuality.VerdictPipeline do
  use Jido.Workflow
  
  def execute(code, context) do
    with {:ok, initial_judge} <- run_judge_unit(code, context),
         {:ok, verification} <- verify_judgment(initial_judge),
         {:ok, final_score} <- aggregate_results([initial_judge, verification]) do
      store_evaluation(final_score, context)
    end
  end
  
  defp run_judge_unit(code, %{budget: budget} = context) do
    model = select_model_by_budget(budget)
    
    prompt = build_evaluation_prompt(code, context)
    
    RubberDuck.LLM.Client.call(model, prompt, 
      temperature: 0.3,
      max_tokens: context.max_tokens || 500
    )
  end
end
```

## Integration points leverage existing quality systems

The LLM judge system should integrate seamlessly with existing code quality infrastructure through strategic touchpoints. For **Code Smell Detection**, the judge enhances static analysis by providing semantic understanding of why certain patterns are problematic and suggesting context-aware refactoring strategies. Rather than replacing tools like SonarQube or ESLint, the judge adds a contextual layer that explains violations in business terms and prioritizes fixes based on actual impact.

For **Anti-Pattern Detection**, LLM judges excel at identifying architectural anti-patterns that static tools miss, such as inappropriate abstraction levels, business logic violations, and cross-cutting concerns. The judge can analyze code in the context of the broader application architecture, identifying patterns like god objects or circular dependencies that require understanding multiple files and their relationships.

The **Testing Validation** system benefits from judges that can assess test quality beyond simple coverage metrics. LLM judges evaluate whether tests actually validate business requirements, identify missing edge cases, and suggest improvements to test structure and assertions. This semantic understanding of test intent significantly improves overall code quality assurance.

```elixir
defmodule RubberDuck.Integration.QualityPipeline do
  use GenServer
  
  def handle_call({:analyze, file_path}, _from, state) do
    # Run static analysis first
    static_results = run_static_analysis(file_path)
    
    # Filter to focus LLM on high-value evaluation
    if requires_deep_analysis?(static_results) do
      llm_evaluation = run_llm_judge(file_path, static_results)
      combined = merge_results(static_results, llm_evaluation)
      {:reply, {:ok, combined}, state}
    else
      {:reply, {:ok, static_results}, state}
    end
  end
  
  defp requires_deep_analysis?(results) do
    results.complexity_score > 10 or
    results.security_issues > 0 or
    results.code_smells > 3
  end
end
```

## Token budgeting system ensures cost-effective operation

Implementing a sophisticated token management system is crucial for sustainable operation. The system should track token usage at multiple granularities—per project, per user, per evaluation type—enabling fine-grained cost control and optimization. Real-time monitoring with configurable alerts at 75%, 90%, and 95% thresholds prevents budget overruns while maintaining service quality.

The budgeting system implements a **tiered evaluation strategy** where initial screening uses lightweight models consuming approximately 500 tokens per evaluation, detailed analysis uses mid-tier models with 2,000 token budgets, and comprehensive reviews reserve 5,000+ tokens for critical code sections. This progressive approach ensures that 70% of evaluations complete within the lightweight tier, achieving significant cost savings while maintaining quality.

```elixir
defmodule RubberDuck.TokenManagement.BudgetAllocator do
  use GenServer
  
  defstruct [:daily_budget, :used_today, :reservations]
  
  def allocate_tokens(evaluation_type, code_complexity) do
    GenServer.call(__MODULE__, {:allocate, evaluation_type, code_complexity})
  end
  
  def handle_call({:allocate, type, complexity}, _from, state) do
    required_tokens = calculate_token_requirement(type, complexity)
    
    if state.used_today + required_tokens <= state.daily_budget do
      new_state = %{state | used_today: state.used_today + required_tokens}
      {:reply, {:ok, required_tokens}, new_state}
    else
      # Fallback to cheaper model or defer evaluation
      {:reply, {:budget_exceeded, suggest_alternative(type)}, state}
    end
  end
  
  defp calculate_token_requirement(:basic_quality, :low), do: 500
  defp calculate_token_requirement(:basic_quality, :medium), do: 1000
  defp calculate_token_requirement(:comprehensive, :high), do: 5000
  defp calculate_token_requirement(:security_audit, _), do: 3000
end
```

Dynamic allocation strategies prioritize critical evaluations like security assessments while deferring non-essential style checks when approaching budget limits. The system maintains a reservation pool for high-priority evaluations and implements predictive analytics to forecast usage patterns, enabling proactive budget adjustments. Integration with the existing cost management infrastructure provides unified reporting across all LLM operations.

## Workflow orchestration implements progressive evaluation

The evaluation workflow leverages Elixir's Reactor pattern to orchestrate complex, multi-stage evaluation pipelines. Each stage implements specific evaluation aspects with appropriate models and token budgets, enabling fine-grained control over the evaluation process. The workflow begins with rapid syntax and style validation using cached patterns and lightweight models, progressing to semantic analysis only when initial checks pass.

```elixir
defmodule RubberDuck.Evaluation.Reactor do
  use Reactor
  
  input :code
  input :context
  
  step :quick_check do
    argument :code, input(:code)
    run fn code ->
      # Lightweight syntax and style check
      case RubberDuck.StaticAnalysis.quick_check(code) do
        {:ok, :pass} -> {:ok, :continue}
        {:ok, issues} when length(issues) > 5 -> {:ok, :skip_detailed}
        {:ok, issues} -> {:ok, {:needs_review, issues}}
      end
    end
  end
  
  step :semantic_analysis do
    wait_for :quick_check
    argument :code, input(:code)
    argument :should_run, result(:quick_check)
    
    run fn code, {:needs_review, _} ->
      RubberDuck.Verdict.JudgeUnit.evaluate(code, 
        model: "gpt-4o-mini",
        criteria: [:correctness, :efficiency],
        max_tokens: 1500
      )
    end
  end
  
  step :security_scan do
    wait_for :quick_check
    argument :code, input(:code)
    
    run fn code ->
      RubberDuck.Verdict.SecurityJudge.analyze(code,
        model: "gpt-4o",
        focus: [:injection, :authentication, :authorization],
        max_tokens: 2000
      )
    end
  end
  
  step :aggregate_results do
    wait_for [:semantic_analysis, :security_scan]
    collect :all_results
    
    run fn results ->
      RubberDuck.Evaluation.Aggregator.combine(results)
    end
  end
end
```

The workflow implements intelligent branching based on code characteristics and evaluation results. High-complexity code triggers additional analysis stages, while simple modifications receive streamlined evaluation. Circuit breakers prevent cascade failures when API services experience issues, automatically falling back to cached results or static analysis. The system maintains evaluation state across retries, ensuring no work is duplicated even during transient failures.

## Prompt engineering optimizes judge effectiveness

Effective prompt design is crucial for consistent, high-quality evaluations. The system implements a multi-layered prompt architecture where base templates define evaluation structure, context injection adds project-specific requirements, and dynamic elements incorporate relevant code patterns and anti-patterns. This approach ensures consistency while maintaining flexibility for different evaluation scenarios.

```elixir
defmodule RubberDuck.Prompts.CodeQualityJudge do
  @base_template """
  You are an expert code reviewer evaluating Elixir code for quality.
  
  CODE TO EVALUATE:
  ```elixir
  <%= @code %>
  ```
  
  EVALUATION CRITERIA:
  1. Correctness: Does the code implement the intended functionality?
  2. Efficiency: Are there performance issues or inefficient patterns?
  3. Maintainability: Is the code clear, well-structured, and documented?
  4. Security: Are there potential vulnerabilities or unsafe practices?
  5. Elixir Best Practices: Does it follow OTP principles and idioms?
  
  For each criterion, provide:
  - Score (1-5): <%= @scoring_rubric %>
  - Specific issues found (if any)
  - Suggested improvements with code examples
  
  Format your response as JSON:
  {
    "correctness": {"score": N, "issues": [], "suggestions": []},
    "efficiency": {"score": N, "issues": [], "suggestions": []},
    "maintainability": {"score": N, "issues": [], "suggestions": []},
    "security": {"score": N, "issues": [], "suggestions": []},
    "best_practices": {"score": N, "issues": [], "suggestions": []},
    "overall_score": N,
    "priority_fixes": []
  }
  """
  
  def build_prompt(code, context) do
    EEx.eval_string(@base_template, 
      assigns: [
        code: code,
        scoring_rubric: get_scoring_rubric(context),
        project_context: context.project_type
      ]
    )
  end
end
```

The prompt engineering strategy incorporates few-shot examples for consistency, explicit anti-bias instructions to prevent common LLM judge issues, and progressive detail levels based on evaluation depth. Chain-of-thought reasoning improves evaluation quality for complex assessments, while structured output formats ensure reliable parsing and integration with downstream systems.

## Metrics and evaluation criteria ensure quality outcomes

The system implements comprehensive metrics tracking both judge performance and code quality improvements. **Judge reliability metrics** include inter-rater agreement between multiple evaluations, correlation with human expert reviews, and temporal consistency for repeated evaluations. These metrics enable continuous calibration and improvement of the judge system.

**Code quality metrics** track improvement trends across multiple dimensions including defect density reduction, technical debt trajectory, security vulnerability trends, and maintainability index changes. The system correlates these metrics with developer productivity indicators to demonstrate ROI and identify optimization opportunities.

```elixir
defmodule RubberDuck.Metrics.EvaluationTracker do
  use GenServer
  
  def track_evaluation(evaluation_result, metadata) do
    GenServer.cast(__MODULE__, {:track, evaluation_result, metadata})
  end
  
  def handle_cast({:track, result, metadata}, state) do
    metrics = %{
      model_used: result.model,
      tokens_consumed: result.token_count,
      evaluation_time: result.duration_ms,
      score_distribution: calculate_distribution(result.scores),
      developer_acceptance: nil  # Updated async when feedback received
    }
    
    # Store in time-series database for analysis
    RubberDuck.Metrics.Store.insert(metrics, metadata)
    
    # Update running statistics
    new_state = update_statistics(state, metrics)
    
    # Check for anomalies or drift
    if detect_drift?(new_state) do
      RubberDuck.Alerts.notify(:evaluation_drift_detected, new_state)
    end
    
    {:noreply, new_state}
  end
end
```

The evaluation criteria adapt based on project context and team maturity. Early-stage projects emphasize correctness and basic security, while mature systems focus on performance optimization and architectural quality. The system learns from developer feedback, adjusting scoring weights and criteria based on which suggestions are accepted or rejected.

## Cost-effective strategies maximize ROI

Implementing a cost-effective LLM judge system requires careful optimization across multiple dimensions. **Model selection strategies** use GPT-4o-mini or Claude-3-Haiku for 80% of evaluations, reserving premium models for security assessments and complex architectural reviews. Multi-model ensembles provide better reliability than single large models while reducing costs by 40-60%.

**Caching strategies** significantly reduce redundant API calls. The system implements semantic caching using code embeddings to identify similar patterns, achieving 30-40% cache hit rates for routine evaluations. Hierarchical caching at function, module, and project levels maximizes reuse while maintaining relevance. The cache invalidation strategy considers both time decay and code change impact.

**Batch processing optimization** groups related evaluations to minimize API overhead. The system accumulates evaluation requests over 5-second windows, batching up to 10 related code snippets per API call. Priority queues ensure critical evaluations aren't delayed by batching, while background processing handles non-urgent reviews during off-peak hours when API rate limits are more generous.

The expected cost structure with these optimizations achieves **$0.01-0.05 per file for basic reviews** and **$0.10-0.30 per file for comprehensive analysis**, representing a 60-80% reduction compared to naive implementation. Most organizations achieve positive ROI within 3-6 months through reduced manual review time, fewer production defects, and improved developer productivity.

## Conclusion

Integrating a Verdict-based LLM judge system into the rubber-duck platform creates a powerful, cost-effective code quality evaluation system that leverages Elixir's strengths while implementing cutting-edge evaluation techniques. The modular architecture enables progressive enhancement and optimization based on actual usage patterns and team needs. By combining Verdict's innovative judge-time compute scaling with Elixir's robust concurrency model and the comprehensive Ash/Jido ecosystem, teams can build production-grade evaluation systems that scale efficiently while maintaining high quality standards.

The key to successful implementation lies in starting simple with basic judge units, then progressively adding sophistication based on measured impact and ROI. The system's modular design ensures that enhancements can be added incrementally without disrupting existing workflows, while comprehensive metrics and monitoring enable data-driven optimization decisions. With proper implementation of the strategies outlined in this guide, organizations can achieve significant improvements in code quality while maintaining reasonable operational costs.
