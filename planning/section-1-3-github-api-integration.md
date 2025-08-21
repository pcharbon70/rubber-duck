# Section 1.3: GitHub API Integration for Data Collection
## Comprehensive Implementation Plan

### Executive Summary

This document outlines the detailed implementation plan for Section 1.3 of the SWE-bench-Elixir project, focusing on GitHub API integration for comprehensive data collection. The implementation will handle rate limiting, pagination, authentication, and Elixir-specific repository patterns including umbrella projects and Hex package metadata.

## Research Findings

### 1. HTTP Client Library Recommendation: **Req**

Based on 2024 ecosystem analysis, **Req** is the recommended HTTP client for this implementation:

**Pros:**
- Modern, batteries-included HTTP client built on Finch
- Functional API that's easier to compose and test than Tesla's module-based approach
- Comprehensive built-in features: authentication, retries, caching, instrumentation
- Step-based pipeline architecture for easy customization
- Likely to become the default HTTP client in future Phoenix versions
- Excellent for building focused API clients vs comprehensive SDK wrappers

**Alternative Consideration: Custom Tentacat vs Req Implementation**
- **Tentacat**: Mature GitHub-specific wrapper, but larger dependency footprint
- **Custom Req**: More control, lighter weight, easier to test and maintain
- **Recommendation**: Custom Req implementation focusing on specific endpoints needed

### 2. Rate Limiting Strategy: **Hammer with Redis Backend**

**Primary Choice: Hammer**
- Pluggable backend system (ETS, Redis, Mnesia)
- Atomic operations for thread safety
- Fixed window counter approach
- Better suited for distributed deployments than ExRated

**Configuration Approach:**
- Redis backend for production scalability
- ETS backend for development/testing
- Multiple rate limit tiers (authenticated vs unauthenticated GitHub API)

### 3. Ecto Schema Design Best Practices

**Key Principles for 2024:**
- Use UUID v7 for better indexing performance with sequential characteristics
- Strategic indexing (avoid over-indexing that impacts write performance)
- Partial indexes for conditional queries
- Explicit constraint handling (database-level + Ecto validation)
- Proper foreign key relationships with cascading behavior

### 4. Testing Strategy: **Mox + Byron for HTTP Mocking**

**Primary Testing Approach:**
- **Mox**: Behavior-based mocking with explicit contracts
- **Byron**: Modern HTTP client mocking for integration tests
- **ExUnit patterns**: Async-safe tests with proper setup/cleanup

## Detailed Implementation Plan

### Task 1.3.1: Implement GitHub API Client

#### 1.3.1.1 Configure HTTP Client with Req
```elixir
# lib/elixir_swe_bench/github/client.ex
defmodule ElixirSweBench.GitHub.Client do
  @moduledoc """
  GitHub API client built with Req for efficient data collection.
  Handles authentication, rate limiting, and response parsing.
  """
  
  @base_url "https://api.github.com"
  @default_headers [
    {"Accept", "application/vnd.github.v3+json"},
    {"User-Agent", "ElixirSweBench/1.0"}
  ]
  
  def new(opts \\ []) do
    Req.new(
      base_url: @base_url,
      headers: @default_headers,
      auth: auth_config(opts),
      retry: retry_config(),
      cache: cache_config()
    )
  end
end
```

**Implementation Details:**
- Configure base Req client with GitHub API v3/v4 endpoints
- Support both personal access tokens and GitHub App authentication
- Implement request/response logging and telemetry
- Add custom steps for GitHub-specific response handling

#### 1.3.1.2 Implement OAuth Authentication Flow
```elixir
# lib/elixir_swe_bench/github/auth.ex
defmodule ElixirSweBench.GitHub.Auth do
  @moduledoc """
  Handles GitHub authentication including OAuth apps and personal tokens.
  Supports automatic token refresh and validation.
  """
  
  defstruct [:token, :type, :expires_at, :scopes]
  
  def authenticate(opts) do
    case Keyword.get(opts, :auth_type, :token) do
      :token -> personal_access_token(opts)
      :oauth -> oauth_flow(opts)
      :github_app -> github_app_auth(opts)
    end
  end
end
```

**Key Features:**
- Personal Access Token (PAT) authentication
- OAuth App flow for user authorization
- GitHub App installation authentication
- Automatic token validation and refresh
- Scope verification for required permissions

#### 1.3.1.3 Handle Rate Limiting with Hammer
```elixir
# lib/elixir_swe_bench/github/rate_limiter.ex
defmodule ElixirSweBench.GitHub.RateLimiter do
  @moduledoc """
  GitHub API rate limiting using Hammer with intelligent backoff.
  Handles both primary and secondary rate limits.
  """
  
  alias ExHammer
  
  @github_limits %{
    authenticated: {5000, 3600},     # 5000 requests per hour
    unauthenticated: {60, 3600},     # 60 requests per hour
    search: {30, 60},                # 30 search requests per minute
    graphql: {5000, 3600}            # 5000 points per hour
  }
  
  def check_rate_limit(client, endpoint_type \\ :authenticated) do
    {limit, window} = @github_limits[endpoint_type]
    bucket = rate_limit_bucket(client, endpoint_type)
    
    case ExHammer.check_rate(bucket, window * 1000, limit) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, :rate_limited}
    end
  end
end
```

**Implementation Strategy:**
- Multiple rate limit buckets for different API endpoints
- Exponential backoff with jitter
- Rate limit header parsing and proactive throttling
- Secondary rate limit detection and handling

#### 1.3.1.4 Implement Pagination with Stream Support
```elixir
# lib/elixir_swe_bench/github/paginator.ex
defmodule ElixirSweBench.GitHub.Paginator do
  @moduledoc """
  Handles GitHub API pagination using Link headers and cursors.
  Provides Stream interface for memory-efficient processing.
  """
  
  def paginate_all(client, url, opts \\ []) do
    Stream.resource(
      fn -> {url, 1} end,
      &fetch_page(client, &1, opts),
      fn _ -> :ok end
    )
    |> Stream.flat_map(& &1)
  end
  
  defp fetch_page(_client, :halt, _opts), do: {:halt, :halt}
  
  defp fetch_page(client, {url, page}, opts) do
    case GitHub.Client.get(client, url, [params: [page: page, per_page: 100] ++ opts]) do
      {:ok, response} ->
        {response.body, next_page_info(response)}
      {:error, _} = error ->
        throw(error)
    end
  end
end
```

**Features:**
- Memory-efficient streaming pagination
- Link header parsing for next/prev pages
- Cursor-based pagination for GraphQL endpoints
- Automatic rate limit handling during pagination

#### 1.3.1.5 Add Request Caching and Persistence
```elixir
# lib/elixir_swe_bench/github/cache.ex
defmodule ElixirSweBench.GitHub.Cache do
  @moduledoc """
  Caching layer for GitHub API responses with ETags and conditional requests.
  Reduces API calls and improves performance.
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get(key, fetch_fn) do
    case lookup_cache(key) do
      {:ok, cached_response} -> conditional_request(key, cached_response, fetch_fn)
      :miss -> fresh_request(key, fetch_fn)
    end
  end
  
  defp conditional_request(key, cached, fetch_fn) do
    case fetch_fn.(etag: cached.etag) do
      {:not_modified, _} -> {:ok, cached.data}
      {:ok, new_data} -> cache_response(key, new_data)
      error -> error
    end
  end
end
```

**Caching Strategy:**
- ETag-based conditional requests to minimize API usage
- Configurable TTL for different data types
- Redis backend for distributed caching
- Automatic cache invalidation on write operations

### Task 1.3.2: Create Repository Analyzer

#### 1.3.2.1 Fetch Repository Metadata and Statistics
```elixir
# lib/elixir_swe_bench/github/repository_analyzer.ex
defmodule ElixirSweBench.GitHub.RepositoryAnalyzer do
  @moduledoc """
  Analyzes GitHub repositories to extract metadata, structure, and statistics
  relevant to SWE-bench-Elixir evaluation.
  """
  
  alias ElixirSweBench.GitHub.Client
  
  def analyze_repository(client, owner, repo) do
    with {:ok, repo_data} <- fetch_repository(client, owner, repo),
         {:ok, languages} <- fetch_languages(client, owner, repo),
         {:ok, topics} <- fetch_topics(client, owner, repo),
         {:ok, structure} <- analyze_project_structure(client, owner, repo) do
      %{
        repository: repo_data,
        languages: languages,
        topics: topics,
        structure: structure,
        elixir_specific: extract_elixir_metadata(structure)
      }
    end
  end
  
  defp extract_elixir_metadata(structure) do
    %{
      project_type: determine_project_type(structure),
      has_hex_package: has_hex_config?(structure),
      umbrella_apps: extract_umbrella_apps(structure),
      test_coverage: estimate_test_coverage(structure)
    }
  end
end
```

**Analysis Capabilities:**
- Basic repository metadata (stars, forks, issues, etc.)
- Language composition and primary language detection
- Topic tags and categorization
- Repository activity metrics (commits, contributors)
- License and documentation analysis

#### 1.3.2.2 Analyze Commit History and Activity
```elixir
# lib/elixir_swe_bench/github/commit_analyzer.ex
defmodule ElixirSweBench.GitHub.CommitAnalyzer do
  @moduledoc """
  Analyzes commit history to understand development patterns,
  code change frequency, and contributor activity.
  """
  
  def analyze_commit_history(client, owner, repo, opts \\ []) do
    timeframe = Keyword.get(opts, :since, days_ago(365))
    
    client
    |> fetch_commits(owner, repo, since: timeframe)
    |> Stream.map(&extract_commit_metadata/1)
    |> Enum.reduce(%{}, &aggregate_commit_stats/2)
    |> calculate_activity_metrics()
  end
  
  defp extract_commit_metadata(commit) do
    %{
      sha: commit["sha"],
      message: commit["commit"]["message"],
      author: commit["commit"]["author"]["name"],
      date: commit["commit"]["author"]["date"],
      files_changed: length(commit["files"] || []),
      additions: commit["stats"]["additions"],
      deletions: commit["stats"]["deletions"]
    }
  end
end
```

**Commit Analysis Features:**
- Development activity patterns (frequency, timing)
- Code churn metrics (additions, deletions, modifications)
- Contributor analysis and diversity
- Commit message analysis for patterns
- File change frequency and hotspots

#### 1.3.2.3 Extract Hex.pm Package Information
```elixir
# lib/elixir_swe_bench/hex/package_analyzer.ex
defmodule ElixirSweBench.Hex.PackageAnalyzer do
  @moduledory """
  Analyzes Hex.pm package information for Elixir repositories.
  Integrates with Hex API to fetch package metadata and stats.
  """
  
  @hex_api_base "https://hex.pm/api"
  
  def analyze_hex_package(package_name) when is_binary(package_name) do
    with {:ok, package_info} <- fetch_package_info(package_name),
         {:ok, downloads} <- fetch_download_stats(package_name),
         {:ok, releases} <- fetch_release_history(package_name) do
      %{
        package: package_info,
        downloads: downloads,
        releases: releases,
        popularity_metrics: calculate_popularity(package_info, downloads),
        stability_metrics: calculate_stability(releases)
      }
    end
  end
  
  def extract_from_mix_exs(mix_exs_content) do
    # Parse mix.exs to extract package information
    # Handle both published and unpublished packages
  end
end
```

**Hex Integration Features:**
- Package metadata (description, licenses, links)
- Download statistics and trends
- Release history and version analysis
- Dependency tree analysis
- Package popularity and stability metrics

#### 1.3.2.4 Identify Umbrella Project Structure
```elixir
# lib/elixir_swe_bench/elixir/project_structure.ex
defmodule ElixirSweBench.Elixir.ProjectStructure do
  @moduledoc """
  Identifies and analyzes Elixir project structures including
  standard, umbrella, and poncho project types.
  """
  
  def analyze_project_structure(client, owner, repo) do
    with {:ok, tree} <- fetch_repository_tree(client, owner, repo) do
      structure = %{
        type: determine_project_type(tree),
        root_files: extract_root_files(tree),
        applications: find_applications(tree),
        test_structure: analyze_test_structure(tree),
        config_files: find_config_files(tree)
      }
      
      {:ok, enrich_with_elixir_specifics(structure)}
    end
  end
  
  defp determine_project_type(tree) do
    cond do
      has_apps_directory?(tree) -> :umbrella
      has_multiple_mix_projects?(tree) -> :poncho
      has_mix_exs?(tree) -> :standard
      true -> :unknown
    end
  end
  
  defp find_applications(tree) do
    tree
    |> Enum.filter(&mix_project?/1)
    |> Enum.map(&extract_app_info/1)
  end
end
```

**Project Structure Analysis:**
- Project type detection (standard, umbrella, poncho)
- Application discovery and dependency mapping
- Test file organization and patterns
- Configuration file analysis
- Build tool and dependency management

#### 1.3.2.5 Calculate Test Coverage from CI Badges
```elixir
# lib/elixir_swe_bench/github/coverage_analyzer.ex
defmodule ElixirSweBench.GitHub.CoverageAnalyzer do
  @moduledoc """
  Analyzes test coverage information from various sources including
  CI badges, coverage reports, and static analysis.
  """
  
  def analyze_test_coverage(client, owner, repo) do
    with {:ok, readme} <- fetch_readme(client, owner, repo),
         {:ok, ci_config} <- fetch_ci_configuration(client, owner, repo) do
      %{
        badge_coverage: extract_coverage_from_badges(readme),
        ci_coverage: extract_coverage_from_ci(ci_config),
        test_files: count_test_files(client, owner, repo),
        coverage_tools: detect_coverage_tools(ci_config)
      }
    end
  end
  
  defp extract_coverage_from_badges(readme_content) do
    ~r/!\[.*coverage.*\]\(.*coveralls.*badge\.svg.*\)/i
    |> Regex.scan(readme_content)
    |> parse_coverage_badges()
  end
end
```

**Coverage Analysis Features:**
- Badge parsing for coverage metrics
- CI configuration analysis
- Test file counting and organization
- Coverage tool detection (ExCoveralls, etc.)
- Historical coverage trends

### Task 1.3.3: Build Issue and PR Collector

#### 1.3.3.1 Fetch Closed Issues with Linked PRs
```elixir
# lib/elixir_swe_bench/github/issue_collector.ex
defmodule ElixirSweBench.GitHub.IssueCollector do
  @moduledoc """
  Collects GitHub issues and their associated pull requests for
  SWE-bench task generation.
  """
  
  def collect_issues_with_prs(client, owner, repo, opts \\ []) do
    filters = build_issue_filters(opts)
    
    client
    |> GitHub.Paginator.paginate_all("/repos/#{owner}/#{repo}/issues", filters)
    |> Stream.filter(&closed_issue_with_pr?/1)
    |> Stream.map(&enrich_with_pr_data(client, &1))
    |> Stream.filter(&suitable_for_benchmark?/1)
    |> Enum.to_list()
  end
  
  defp closed_issue_with_pr?(issue) do
    issue["state"] == "closed" and
      issue["pull_request"] != nil and
      has_linked_pr?(issue)
  end
  
  defp suitable_for_benchmark?(issue_with_pr) do
    # Filter for issues that are suitable for benchmarking
    has_test_changes?(issue_with_pr.pr) and
      reasonable_complexity?(issue_with_pr) and
      clear_problem_description?(issue_with_pr.issue)
  end
end
```

**Issue Collection Criteria:**
- Closed issues with successful PR resolution
- Issues with clear problem descriptions
- PRs that include test modifications
- Reasonable complexity for automation
- Adequate documentation and context

#### 1.3.3.2 Extract PR Diff and Patch Content
```elixir
# lib/elixir_swe_bench/github/diff_extractor.ex
defmodule ElixirSweBench.GitHub.DiffExtractor do
  @moduledoc """
  Extracts and analyzes diff content from GitHub pull requests.
  Focuses on code changes, test modifications, and impact analysis.
  """
  
  def extract_pr_diff(client, owner, repo, pr_number) do
    with {:ok, pr_data} <- fetch_pr_details(client, owner, repo, pr_number),
         {:ok, diff_data} <- fetch_pr_diff(client, owner, repo, pr_number),
         {:ok, files} <- fetch_pr_files(client, owner, repo, pr_number) do
      %{
        pr: pr_data,
        diff: parse_diff_content(diff_data),
        files: analyze_changed_files(files),
        impact: calculate_change_impact(files)
      }
    end
  end
  
  defp analyze_changed_files(files) do
    Enum.map(files, fn file ->
      %{
        filename: file["filename"],
        status: file["status"],  # added, modified, removed
        additions: file["additions"],
        deletions: file["deletions"],
        changes: file["changes"],
        patch: parse_patch_content(file["patch"]),
        file_type: classify_file_type(file["filename"])
      }
    end)
  end
  
  defp classify_file_type(filename) do
    cond do
      String.ends_with?(filename, "_test.exs") -> :test_file
      String.ends_with?(filename, ".exs") -> :script_file
      String.ends_with?(filename, ".ex") -> :source_file
      String.contains?(filename, "mix.exs") -> :build_file
      String.contains?(filename, "config/") -> :config_file
      true -> :other
    end
  end
end
```

**Diff Analysis Features:**
- Complete diff content parsing
- File-level change analysis
- Line-by-line modification tracking
- Change impact assessment
- Test vs. production code separation

#### 1.3.3.3 Identify Test File Modifications
```elixir
# lib/elixir_swe_bench/github/test_analyzer.ex
defmodule ElixirSweBench.GitHub.TestAnalyzer do
  @moduledoc """
  Analyzes test file modifications in pull requests to understand
  testing patterns and validate benchmark suitability.
  """
  
  def analyze_test_changes(pr_files) do
    test_files = Enum.filter(pr_files, &test_file?/1)
    
    %{
      test_files_modified: length(test_files),
      test_changes: Enum.map(test_files, &analyze_test_file_changes/1),
      new_tests_added: count_new_tests(test_files),
      existing_tests_modified: count_modified_tests(test_files),
      test_patterns: identify_test_patterns(test_files)
    }
  end
  
  defp analyze_test_file_changes(file) do
    patch_lines = parse_patch_lines(file.patch)
    
    %{
      file: file.filename,
      new_test_functions: extract_new_test_functions(patch_lines),
      modified_test_functions: extract_modified_test_functions(patch_lines),
      assertion_changes: analyze_assertion_changes(patch_lines),
      setup_changes: analyze_setup_changes(patch_lines)
    }
  end
  
  defp extract_new_test_functions(patch_lines) do
    patch_lines
    |> Enum.filter(&added_line?/1)
    |> Enum.filter(&test_function_definition?/1)
    |> Enum.map(&extract_test_function_name/1)
  end
end
```

**Test Analysis Capabilities:**
- Test file identification and classification
- New vs. modified test detection
- Assertion pattern analysis
- Test setup and teardown changes
- Testing framework usage patterns

#### 1.3.3.4 Parse PR Review Comments for Context
```elixir
# lib/elixir_swe_bench/github/review_analyzer.ex
defmodule ElixirSweBench.GitHub.ReviewAnalyzer do
  @moduledoc """
  Analyzes PR review comments to extract additional context
  about the changes and implementation decisions.
  """
  
  def analyze_pr_reviews(client, owner, repo, pr_number) do
    with {:ok, reviews} <- fetch_pr_reviews(client, owner, repo, pr_number),
         {:ok, comments} <- fetch_pr_comments(client, owner, repo, pr_number) do
      %{
        reviews: analyze_reviews(reviews),
        comments: analyze_comments(comments),
        feedback_themes: extract_feedback_themes(reviews ++ comments),
        approval_status: determine_approval_status(reviews)
      }
    end
  end
  
  defp analyze_reviews(reviews) do
    Enum.map(reviews, fn review ->
      %{
        user: review["user"]["login"],
        state: review["state"],  # APPROVED, CHANGES_REQUESTED, COMMENTED
        body: review["body"],
        submitted_at: review["submitted_at"],
        sentiment: analyze_sentiment(review["body"])
      }
    end)
  end
  
  defp extract_feedback_themes(comments) do
    comments
    |> Enum.map(& &1["body"])
    |> Enum.join(" ")
    |> analyze_for_common_themes()
  end
end
```

**Review Analysis Features:**
- Review state tracking (approved, changes requested)
- Comment sentiment analysis
- Feedback theme extraction
- Code quality discussions
- Implementation approach debates

#### 1.3.3.5 Track Function and Module Changes
```elixir
# lib/elixir_swe_bench/elixir/code_analyzer.ex
defmodule ElixirSweBench.Elixir.CodeAnalyzer do
  @moduledoc """
  Analyzes Elixir code changes at the function and module level.
  Provides detailed insights into structural modifications.
  """
  
  def analyze_code_changes(pr_files) do
    elixir_files = Enum.filter(pr_files, &elixir_file?/1)
    
    Enum.map(elixir_files, fn file ->
      %{
        file: file.filename,
        module_changes: analyze_module_changes(file),
        function_changes: analyze_function_changes(file),
        macro_changes: analyze_macro_changes(file),
        attribute_changes: analyze_attribute_changes(file),
        import_changes: analyze_import_changes(file)
      }
    end)
  end
  
  defp analyze_function_changes(file) do
    patch_lines = parse_patch_lines(file.patch)
    
    %{
      new_functions: extract_new_functions(patch_lines),
      modified_functions: extract_modified_functions(patch_lines),
      removed_functions: extract_removed_functions(patch_lines),
      function_signatures: extract_signature_changes(patch_lines)
    }
  end
  
  defp extract_new_functions(patch_lines) do
    patch_lines
    |> Enum.filter(&added_line?/1)
    |> Enum.filter(&function_definition?/1)
    |> Enum.map(&parse_function_signature/1)
  end
end
```

**Code Analysis Features:**
- Module-level change tracking
- Function addition, modification, removal
- Function signature analysis
- Macro and attribute changes
- Import and alias modifications

### Task 1.3.4: Implement Data Persistence Layer

#### 1.3.4.1 Design Ecto Schemas for Repositories
```elixir
# lib/elixir_swe_bench/github/schema/repository.ex
defmodule ElixirSweBench.GitHub.Schema.Repository do
  @moduledoc """
  Ecto schema for GitHub repository data with Elixir-specific metadata.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  
  schema "repositories" do
    field :github_id, :integer
    field :owner, :string
    field :name, :string
    field :full_name, :string
    field :description, :string
    field :url, :string
    field :clone_url, :string
    field :default_branch, :string
    field :primary_language, :string
    field :license, :string
    
    # Statistics
    field :stars_count, :integer
    field :forks_count, :integer
    field :open_issues_count, :integer
    field :subscribers_count, :integer
    field :size, :integer
    
    # Elixir-specific metadata
    field :project_type, Ecto.Enum, values: [:standard, :umbrella, :poncho, :unknown]
    field :has_hex_package, :boolean, default: false
    field :hex_package_name, :string
    field :elixir_version, :string
    field :otp_version, :string
    
    # Analysis metadata
    field :last_analyzed_at, :utc_datetime
    field :analysis_version, :string
    field :is_active, :boolean, default: true
    field :suitability_score, :float
    
    # Associations
    has_many :issues, ElixirSweBench.GitHub.Schema.Issue
    has_many :pull_requests, ElixirSweBench.GitHub.Schema.PullRequest
    has_many :task_instances, ElixirSweBench.GitHub.Schema.TaskInstance
    
    embeds_one :languages, LanguageStats do
      field :elixir_percentage, :float
      field :total_lines, :integer
      field :language_distribution, :map
    end
    
    embeds_one :activity_stats, ActivityStats do
      field :commits_last_year, :integer
      field :contributors_count, :integer
      field :avg_commits_per_month, :float
      field :last_commit_at, :utc_datetime
    end
    
    embeds_many :umbrella_apps, UmbrellaApp do
      field :name, :string
      field :path, :string
      field :description, :string
      field :has_tests, :boolean
    end
    
    timestamps(type: :utc_datetime)
  end
  
  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [
      :github_id, :owner, :name, :full_name, :description, :url, :clone_url,
      :default_branch, :primary_language, :license, :stars_count, :forks_count,
      :open_issues_count, :subscribers_count, :size, :project_type,
      :has_hex_package, :hex_package_name, :elixir_version, :otp_version,
      :last_analyzed_at, :analysis_version, :is_active, :suitability_score
    ])
    |> cast_embed(:languages)
    |> cast_embed(:activity_stats)
    |> cast_embed(:umbrella_apps)
    |> validate_required([
      :github_id, :owner, :name, :full_name, :url, :clone_url, :default_branch
    ])
    |> validate_inclusion(:project_type, [:standard, :umbrella, :poncho, :unknown])
    |> validate_number(:suitability_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint(:github_id)
    |> unique_constraint([:owner, :name])
  end
end
```

#### 1.3.4.2 Create Schemas for Issues and PRs
```elixir
# lib/elixir_swe_bench/github/schema/issue.ex
defmodule ElixirSweBench.GitHub.Schema.Issue do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  
  schema "issues" do
    field :github_id, :integer
    field :number, :integer
    field :title, :string
    field :body, :string
    field :state, Ecto.Enum, values: [:open, :closed]
    field :labels, {:array, :string}
    field :assignees, {:array, :string}
    field :milestone, :string
    field :created_at_github, :utc_datetime
    field :updated_at_github, :utc_datetime
    field :closed_at_github, :utc_datetime
    
    # Analysis metadata
    field :complexity_score, :float
    field :has_linked_pr, :boolean
    field :is_suitable_for_benchmark, :boolean
    field :problem_category, :string
    field :requires_domain_knowledge, :boolean
    
    # Relationships
    belongs_to :repository, ElixirSweBench.GitHub.Schema.Repository
    has_many :pull_requests, ElixirSweBench.GitHub.Schema.PullRequest, foreign_key: :closes_issue_id
    has_many :task_instances, ElixirSweBench.GitHub.Schema.TaskInstance
    
    embeds_one :author, Author do
      field :login, :string
      field :avatar_url, :string
      field :user_type, :string
    end
    
    timestamps(type: :utc_datetime)
  end
end

# lib/elixir_swe_bench/github/schema/pull_request.ex
defmodule ElixirSweBench.GitHub.Schema.PullRequest do
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  
  schema "pull_requests" do
    field :github_id, :integer
    field :number, :integer
    field :title, :string
    field :body, :string
    field :state, Ecto.Enum, values: [:open, :closed, :merged]
    field :merged, :boolean
    field :mergeable, :boolean
    field :head_sha, :string
    field :base_sha, :string
    field :merge_commit_sha, :string
    field :diff_url, :string
    field :patch_url, :string
    
    # Statistics
    field :additions, :integer
    field :deletions, :integer
    field :changed_files, :integer
    field :commits, :integer
    field :review_comments, :integer
    field :comments, :integer
    
    # Analysis
    field :affects_tests, :boolean
    field :test_files_modified, :integer
    field :complexity_score, :float
    
    # Relationships
    belongs_to :repository, ElixirSweBench.GitHub.Schema.Repository
    belongs_to :closes_issue, ElixirSweBench.GitHub.Schema.Issue, foreign_key: :closes_issue_id
    has_many :task_instances, ElixirSweBench.GitHub.Schema.TaskInstance
    
    embeds_one :author, Author do
      field :login, :string
      field :avatar_url, :string
      field :user_type, :string
    end
    
    embeds_many :changed_files, ChangedFile do
      field :filename, :string
      field :status, Ecto.Enum, values: [:added, :modified, :removed, :renamed]
      field :additions, :integer
      field :deletions, :integer
      field :changes, :integer
      field :patch, :string
      field :file_type, Ecto.Enum, values: [:source_file, :test_file, :config_file, :build_file, :other]
    end
    
    timestamps(type: :utc_datetime)
  end
end
```

#### 1.3.4.3 Store Task Instances with Metadata
```elixir
# lib/elixir_swe_bench/github/schema/task_instance.ex
defmodule ElixirSweBench.GitHub.Schema.TaskInstance do
  @moduledoc """
  Represents a single SWE-bench task instance generated from a GitHub issue/PR pair.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  
  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @foreign_key_type Ecto.UUID
  
  schema "task_instances" do
    field :instance_id, :string  # Unique identifier for the task (repo_owner__repo_name__issue_number)
    field :task_type, Ecto.Enum, values: [:bug_fix, :feature_addition, :refactor, :performance, :documentation]
    field :difficulty_level, Ecto.Enum, values: [:easy, :medium, :hard, :expert]
    field :estimated_time_minutes, :integer
    
    # Task content
    field :problem_statement, :string
    field :solution_patch, :string
    field :test_patch, :string
    field :base_commit, :string
    field :solution_commit, :string
    
    # Validation data
    field :original_test_results, :map
    field :patched_test_results, :map
    field :validation_status, Ecto.Enum, values: [:pending, :valid, :invalid, :needs_review]
    field :validation_errors, {:array, :string}
    
    # Metadata
    field :created_by_version, :string
    field :is_active, :boolean, default: true
    field :quality_score, :float
    field :complexity_metrics, :map
    
    # Relationships
    belongs_to :repository, ElixirSweBench.GitHub.Schema.Repository
    belongs_to :issue, ElixirSweBench.GitHub.Schema.Issue
    belongs_to :pull_request, ElixirSweBench.GitHub.Schema.PullRequest
    
    embeds_one :elixir_context, ElixirContext do
      field :affected_modules, {:array, :string}
      field :affected_functions, {:array, :string}
      field :test_modules_affected, {:array, :string}
      field :dependencies_changed, {:array, :string}
      field :config_changes_required, :boolean
      field :requires_database_migration, :boolean
    end
    
    embeds_one :evaluation_metadata, EvaluationMetadata do
      field :timeout_seconds, :integer, default: 300
      field :memory_limit_mb, :integer, default: 4096
      field :requires_external_services, :boolean, default: false
      field :environment_requirements, {:array, :string}
      field :setup_commands, {:array, :string}
    end
    
    timestamps(type: :utc_datetime)
  end
  
  def changeset(task_instance, attrs) do
    task_instance
    |> cast(attrs, [
      :instance_id, :task_type, :difficulty_level, :estimated_time_minutes,
      :problem_statement, :solution_patch, :test_patch, :base_commit,
      :solution_commit, :validation_status, :validation_errors,
      :created_by_version, :is_active, :quality_score
    ])
    |> cast_embed(:elixir_context)
    |> cast_embed(:evaluation_metadata)
    |> put_change(:original_test_results, attrs[:original_test_results] || %{})
    |> put_change(:patched_test_results, attrs[:patched_test_results] || %{})
    |> put_change(:complexity_metrics, attrs[:complexity_metrics] || %{})
    |> validate_required([
      :instance_id, :task_type, :difficulty_level, :problem_statement,
      :solution_patch, :base_commit, :solution_commit
    ])
    |> validate_inclusion(:task_type, [:bug_fix, :feature_addition, :refactor, :performance, :documentation])
    |> validate_inclusion(:difficulty_level, [:easy, :medium, :hard, :expert])
    |> validate_inclusion(:validation_status, [:pending, :valid, :invalid, :needs_review])
    |> validate_number(:quality_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint(:instance_id)
  end
end
```

#### 1.3.4.4 Implement Data Deduplication
```elixir
# lib/elixir_swe_bench/github/data_deduplicator.ex
defmodule ElixirSweBench.GitHub.DataDeduplicator do
  @moduledoc """
  Handles deduplication of GitHub data to prevent duplicate entries
  and ensure data consistency across updates.
  """
  
  alias ElixirSweBench.Repo
  alias ElixirSweBench.GitHub.Schema.{Repository, Issue, PullRequest}
  
  def upsert_repository(github_data) do
    case Repo.get_by(Repository, github_id: github_data.github_id) do
      nil ->
        %Repository{}
        |> Repository.changeset(github_data)
        |> Repo.insert()
      
      existing ->
        existing
        |> Repository.changeset(merge_repository_data(existing, github_data))
        |> Repo.update()
    end
  end
  
  def upsert_issue(repo_id, github_data) do
    case Repo.get_by(Issue, github_id: github_data.github_id, repository_id: repo_id) do
      nil ->
        github_data
        |> Map.put(:repository_id, repo_id)
        |> then(&Issue.changeset(%Issue{}, &1))
        |> Repo.insert()
      
      existing ->
        existing
        |> Issue.changeset(merge_issue_data(existing, github_data))
        |> Repo.update()
    end
  end
  
  defp merge_repository_data(existing, new_data) do
    # Smart merge that preserves manual overrides while updating GitHub data
    new_data
    |> Map.put(:last_analyzed_at, DateTime.utc_now())
    |> Map.put(:analysis_version, Application.get_env(:elixir_swe_bench, :version))
    |> preserve_manual_overrides(existing)
  end
  
  defp preserve_manual_overrides(new_data, existing) do
    # Preserve manually set fields that shouldn't be overwritten by GitHub updates
    manual_fields = [:suitability_score, :is_active, :hex_package_name]
    
    Enum.reduce(manual_fields, new_data, fn field, acc ->
      if Map.get(existing, field) != nil and manually_set?(existing, field) do
        Map.put(acc, field, Map.get(existing, field))
      else
        acc
      end
    end)
  end
end
```

#### 1.3.4.5 Add Indexing for Efficient Queries
```elixir
# priv/repo/migrations/20241120000001_create_github_tables.exs
defmodule ElixirSweBench.Repo.Migrations.CreateGithubTables do
  use Ecto.Migration
  
  def up do
    # Enable UUID extension
    execute "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\""
    execute "CREATE EXTENSION IF NOT EXISTS \"pg_trgm\""
    
    create table(:repositories, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
      add :github_id, :integer, null: false
      add :owner, :string, null: false
      add :name, :string, null: false
      add :full_name, :string, null: false
      add :description, :text
      add :url, :string, null: false
      add :clone_url, :string, null: false
      add :default_branch, :string, null: false
      add :primary_language, :string
      add :license, :string
      
      # Statistics
      add :stars_count, :integer, default: 0
      add :forks_count, :integer, default: 0
      add :open_issues_count, :integer, default: 0
      add :subscribers_count, :integer, default: 0
      add :size, :integer, default: 0
      
      # Elixir-specific metadata
      add :project_type, :string, null: false, default: "unknown"
      add :has_hex_package, :boolean, default: false
      add :hex_package_name, :string
      add :elixir_version, :string
      add :otp_version, :string
      
      # Analysis metadata
      add :last_analyzed_at, :utc_datetime
      add :analysis_version, :string
      add :is_active, :boolean, default: true
      add :suitability_score, :float
      
      # JSON columns for complex data
      add :languages, :jsonb
      add :activity_stats, :jsonb
      add :umbrella_apps, :jsonb
      
      timestamps(type: :utc_datetime)
    end
    
    # Repository indexes
    create unique_index(:repositories, [:github_id])
    create unique_index(:repositories, [:owner, :name])
    create index(:repositories, [:primary_language])
    create index(:repositories, [:project_type])
    create index(:repositories, [:has_hex_package])
    create index(:repositories, [:is_active])
    create index(:repositories, [:suitability_score])
    create index(:repositories, [:stars_count])
    create index(:repositories, [:last_analyzed_at])
    
    # GIN indexes for JSONB columns
    create index(:repositories, [:languages], using: "gin")
    create index(:repositories, [:activity_stats], using: "gin")
    
    # Full-text search index
    create index(:repositories, [:full_name, :description], using: "gin", prefix: :gin_trgm_ops)
    
    create table(:issues, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :github_id, :integer, null: false
      add :number, :integer, null: false
      add :title, :string, null: false
      add :body, :text
      add :state, :string, null: false
      add :labels, {:array, :string}, default: []
      add :assignees, {:array, :string}, default: []
      add :milestone, :string
      add :created_at_github, :utc_datetime, null: false
      add :updated_at_github, :utc_datetime, null: false
      add :closed_at_github, :utc_datetime
      
      # Analysis metadata
      add :complexity_score, :float
      add :has_linked_pr, :boolean, default: false
      add :is_suitable_for_benchmark, :boolean, default: false
      add :problem_category, :string
      add :requires_domain_knowledge, :boolean, default: false
      
      # JSON columns
      add :author, :jsonb
      
      timestamps(type: :utc_datetime)
    end
    
    # Issue indexes
    create unique_index(:issues, [:github_id])
    create unique_index(:issues, [:repository_id, :number])
    create index(:issues, [:repository_id, :state])
    create index(:issues, [:has_linked_pr])
    create index(:issues, [:is_suitable_for_benchmark])
    create index(:issues, [:problem_category])
    create index(:issues, [:complexity_score])
    create index(:issues, [:closed_at_github])
    create index(:issues, [:labels], using: "gin")
    
    # Full-text search on issues
    create index(:issues, [:title, :body], using: "gin", prefix: :gin_trgm_ops)
    
    create table(:pull_requests, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :closes_issue_id, references(:issues, type: :uuid, on_delete: :nullify)
      add :github_id, :integer, null: false
      add :number, :integer, null: false
      add :title, :string, null: false
      add :body, :text
      add :state, :string, null: false
      add :merged, :boolean, default: false
      add :mergeable, :boolean
      add :head_sha, :string, null: false
      add :base_sha, :string, null: false
      add :merge_commit_sha, :string
      add :diff_url, :string
      add :patch_url, :string
      
      # Statistics
      add :additions, :integer, default: 0
      add :deletions, :integer, default: 0
      add :changed_files, :integer, default: 0
      add :commits, :integer, default: 0
      add :review_comments, :integer, default: 0
      add :comments, :integer, default: 0
      
      # Analysis
      add :affects_tests, :boolean, default: false
      add :test_files_modified, :integer, default: 0
      add :complexity_score, :float
      
      # JSON columns
      add :author, :jsonb
      add :changed_files, :jsonb
      
      timestamps(type: :utc_datetime)
    end
    
    # Pull request indexes
    create unique_index(:pull_requests, [:github_id])
    create unique_index(:pull_requests, [:repository_id, :number])
    create index(:pull_requests, [:repository_id, :state])
    create index(:pull_requests, [:closes_issue_id])
    create index(:pull_requests, [:merged])
    create index(:pull_requests, [:affects_tests])
    create index(:pull_requests, [:complexity_score])
    create index(:pull_requests, [:head_sha])
    create index(:pull_requests, [:base_sha])
    create index(:pull_requests, [:merge_commit_sha])
    
    create table(:task_instances, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("uuid_generate_v7()")
      add :repository_id, references(:repositories, type: :uuid, on_delete: :delete_all), null: false
      add :issue_id, references(:issues, type: :uuid, on_delete: :delete_all), null: false
      add :pull_request_id, references(:pull_requests, type: :uuid, on_delete: :delete_all), null: false
      add :instance_id, :string, null: false
      add :task_type, :string, null: false
      add :difficulty_level, :string, null: false
      add :estimated_time_minutes, :integer
      
      # Task content
      add :problem_statement, :text, null: false
      add :solution_patch, :text, null: false
      add :test_patch, :text
      add :base_commit, :string, null: false
      add :solution_commit, :string, null: false
      
      # Validation data
      add :original_test_results, :jsonb
      add :patched_test_results, :jsonb
      add :validation_status, :string, null: false, default: "pending"
      add :validation_errors, {:array, :string}, default: []
      
      # Metadata
      add :created_by_version, :string, null: false
      add :is_active, :boolean, default: true
      add :quality_score, :float
      add :complexity_metrics, :jsonb
      
      # JSON columns
      add :elixir_context, :jsonb
      add :evaluation_metadata, :jsonb
      
      timestamps(type: :utc_datetime)
    end
    
    # Task instance indexes
    create unique_index(:task_instances, [:instance_id])
    create index(:task_instances, [:repository_id])
    create index(:task_instances, [:issue_id])
    create index(:task_instances, [:pull_request_id])
    create index(:task_instances, [:task_type])
    create index(:task_instances, [:difficulty_level])
    create index(:task_instances, [:validation_status])
    create index(:task_instances, [:is_active])
    create index(:task_instances, [:quality_score])
    create index(:task_instances, [:created_by_version])
    
    # Composite indexes for common queries
    create index(:task_instances, [:repository_id, :task_type])
    create index(:task_instances, [:validation_status, :is_active])
    create index(:task_instances, [:difficulty_level, :quality_score])
    
    # GIN indexes for JSONB columns
    create index(:task_instances, [:complexity_metrics], using: "gin")
    create index(:task_instances, [:elixir_context], using: "gin")
    create index(:task_instances, [:evaluation_metadata], using: "gin")
  end
  
  def down do
    drop table(:task_instances)
    drop table(:pull_requests)
    drop table(:issues)
    drop table(:repositories)
    
    execute "DROP EXTENSION IF EXISTS \"pg_trgm\""
    execute "DROP EXTENSION IF EXISTS \"uuid-ossp\""
  end
end
```

### Unit Tests Implementation

#### 1.3.5 Test API Authentication and Rate Limiting
```elixir
# test/elixir_swe_bench/github/client_test.exs
defmodule ElixirSweBench.GitHub.ClientTest do
  use ExUnit.Case, async: true
  
  import Mox
  
  alias ElixirSweBench.GitHub.{Client, Auth, RateLimiter}
  
  setup :verify_on_exit!
  
  describe "authentication" do
    test "configures personal access token authentication" do
      token = "ghp_test_token"
      client = Client.new(auth: {:token, token})
      
      assert {:ok, response} = Client.get(client, "/user")
      assert response.request.headers["authorization"] == "Bearer #{token}"
    end
    
    test "handles OAuth authentication flow" do
      # Mock OAuth flow
      ElixirSweBench.GitHub.MockClient
      |> expect(:post, fn "/login/oauth/access_token", _params ->
        {:ok, %{body: %{"access_token" => "oauth_token"}}}
      end)
      
      auth = Auth.authenticate(auth_type: :oauth, client_id: "test", client_secret: "secret", code: "code")
      assert {:ok, %Auth{token: "oauth_token", type: :oauth}} = auth
    end
    
    test "validates token permissions and scopes" do
      # Test scope validation
      client = Client.new(auth: {:token, "limited_token"})
      
      ElixirSweBench.GitHub.MockClient
      |> expect(:get, fn "/user", _opts ->
        {:ok, %{headers: [{"x-oauth-scopes", "repo,read:user"}]}}
      end)
      
      assert {:ok, scopes} = Auth.validate_scopes(client)
      assert "repo" in scopes
      assert "read:user" in scopes
    end
  end
  
  describe "rate limiting" do
    test "respects GitHub API rate limits" do
      client = Client.new(auth: {:token, "test_token"})
      
      # Simulate rate limit hit
      ElixirSweBench.GitHub.MockClient
      |> expect(:get, 60, fn "/user", _opts ->
        {:ok, %{status: 200, headers: [{"x-ratelimit-remaining", "0"}]}}
      end)
      |> expect(:get, fn "/user", _opts ->
        {:error, %{status: 403, body: %{"message" => "API rate limit exceeded"}}}
      end)
      
      # Should succeed 60 times, then fail
      for _ <- 1..60 do
        assert {:ok, _} = Client.get(client, "/user")
      end
      
      assert {:error, :rate_limited} = Client.get(client, "/user")
    end
    
    test "implements exponential backoff on rate limit" do
      start_time = System.monotonic_time(:millisecond)
      
      # Mock rate limited response followed by success
      ElixirSweBench.GitHub.MockClient
      |> expect(:get, fn "/user", _opts ->
        {:error, %{status: 403, headers: [{"retry-after", "2"}]}}
      end)
      |> expect(:get, fn "/user", _opts ->
        {:ok, %{status: 200, body: %{}}}
      end)
      
      assert {:ok, _} = Client.get_with_retry(Client.new(), "/user")
      
      end_time = System.monotonic_time(:millisecond)
      assert end_time - start_time >= 2000  # Should wait at least 2 seconds
    end
  end
end
```

#### 1.3.6 Test Pagination Handling for Large Datasets
```elixir
# test/elixir_swe_bench/github/paginator_test.exs
defmodule ElixirSweBench.GitHub.PaginatorTest do
  use ExUnit.Case, async: true
  
  import Mox
  
  alias ElixirSweBench.GitHub.{Client, Paginator}
  
  setup :verify_on_exit!
  
  describe "pagination" do
    test "handles Link header pagination" do
      client = Client.new()
      
      # Mock paginated responses
      ElixirSweBench.GitHub.MockClient
      |> expect(:get, fn "/repos/owner/repo/issues", [params: [page: 1, per_page: 100]] ->
        {:ok, %{
          status: 200,
          body: [%{"number" => 1}, %{"number" => 2}],
          headers: [{"link", "<https://api.github.com/repos/owner/repo/issues?page=2>; rel=\"next\""}]
        }}
      end)
      |> expect(:get, fn "/repos/owner/repo/issues", [params: [page: 2, per_page: 100]] ->
        {:ok, %{
          status: 200,
          body: [%{"number" => 3}, %{"number" => 4}],
          headers: []
        }}
      end)
      
      results = 
        client
        |> Paginator.paginate_all("/repos/owner/repo/issues")
        |> Enum.to_list()
      
      assert length(results) == 4
      assert Enum.map(results, & &1["number"]) == [1, 2, 3, 4]
    end
    
    test "handles GraphQL cursor pagination" do
      client = Client.new()
      
      ElixirSweBench.GitHub.MockClient
      |> expect(:post, fn "/graphql", %{query: query} when is_binary(query) ->
        {:ok, %{
          body: %{
            "data" => %{
              "repository" => %{
                "issues" => %{
                  "edges" => [
                    %{"node" => %{"number" => 1}},
                    %{"node" => %{"number" => 2}}
                  ],
                  "pageInfo" => %{
                    "hasNextPage" => true,
                    "endCursor" => "cursor123"
                  }
                }
              }
            }
          }
        }}
      end)
      |> expect(:post, fn "/graphql", %{query: query} when is_binary(query) ->
        {:ok, %{
          body: %{
            "data" => %{
              "repository" => %{
                "issues" => %{
                  "edges" => [
                    %{"node" => %{"number" => 3}}
                  ],
                  "pageInfo" => %{
                    "hasNextPage" => false,
                    "endCursor" => nil
                  }
                }
              }
            }
          }
        }}
      end)
      
      results = 
        client
        |> Paginator.paginate_graphql(build_issues_query("owner", "repo"))
        |> Enum.to_list()
      
      assert length(results) == 3
    end
    
    test "handles rate limiting during pagination" do
      client = Client.new()
      
      ElixirSweBench.GitHub.MockClient
      |> expect(:get, fn _, _ ->
        {:ok, %{body: [%{"number" => 1}], headers: []}}
      end)
      |> expect(:get, fn _, _ ->
        {:error, %{status: 403, body: %{"message" => "API rate limit exceeded"}}}
      end)
      |> expect(:get, fn _, _ ->
        {:ok, %{body: [%{"number" => 2}], headers: []}}
      end)
      
      results = 
        client
        |> Paginator.paginate_all("/repos/owner/repo/issues")
        |> Enum.to_list()
      
      # Should eventually succeed despite rate limiting
      assert length(results) == 2
    end
  end
end
```

#### 1.3.7-1.3.11 Additional Test Suites
```elixir
# test/elixir_swe_bench/github/repository_analyzer_test.exs
defmodule ElixirSweBench.GitHub.RepositoryAnalyzerTest do
  use ExUnit.Case, async: true
  import Mox
  
  describe "repository metadata extraction" do
    test "analyzes Elixir project structure correctly" do
      # Test implementation for umbrella project detection
    end
    
    test "extracts Hex package information" do
      # Test Hex.pm integration
    end
    
    test "calculates repository suitability score" do
      # Test suitability scoring algorithm
    end
  end
end

# test/elixir_swe_bench/github/issue_collector_test.exs  
defmodule ElixirSweBench.GitHub.IssueCollectorTest do
  use ExUnit.Case, async: true
  
  describe "issue and PR collection" do
    test "identifies issues with linked PRs" do
      # Test issue-PR relationship detection
    end
    
    test "filters suitable issues for benchmarking" do
      # Test issue filtering criteria
    end
  end
end

# test/elixir_swe_bench/github/schema_test.exs
defmodule ElixirSweBench.GitHub.SchemaTest do
  use ElixirSweBench.DataCase, async: true
  
  describe "data persistence" do
    test "validates repository schema constraints" do
      # Test Ecto schema validation
    end
    
    test "handles data deduplication correctly" do
      # Test upsert operations
    end
    
    test "maintains referential integrity" do
      # Test foreign key relationships
    end
  end
end
```

## Integration Strategy

### Development Phases

**Phase 1 (Weeks 1-2): Core HTTP Client**
- Implement Req-based GitHub client
- Add authentication and rate limiting
- Basic pagination support
- Unit tests for client functionality

**Phase 2 (Weeks 3-4): Data Collection**
- Repository analyzer implementation
- Issue and PR collector
- Hex.pm integration
- Comprehensive test coverage

**Phase 3 (Weeks 5-6): Data Persistence**
- Ecto schema implementation
- Database migrations and indexing
- Data deduplication logic
- Performance optimization

**Phase 4 (Weeks 7-8): Integration & Validation**
- End-to-end integration tests
- Performance benchmarking
- Error handling and resilience
- Documentation and deployment preparation

### Configuration Management

```elixir
# config/config.exs
config :elixir_swe_bench, ElixirSweBench.GitHub,
  api_base_url: "https://api.github.com",
  graphql_endpoint: "https://api.github.com/graphql",
  rate_limit_backend: :redis,  # or :ets for dev/test
  cache_backend: :redis,
  request_timeout: 30_000,
  max_retries: 3,
  backoff_base: 1000

config :elixir_swe_bench, ElixirSweBench.Hex,
  api_base_url: "https://hex.pm/api",
  cache_ttl: 3600

# config/dev.exs
config :elixir_swe_bench, ElixirSweBench.GitHub,
  rate_limit_backend: :ets,
  cache_backend: :ets

# config/test.exs  
config :elixir_swe_bench, ElixirSweBench.GitHub,
  client: ElixirSweBench.GitHub.MockClient,
  rate_limit_backend: :ets,
  cache_backend: :ets
```

### Monitoring and Observability

```elixir
# lib/elixir_swe_bench/github/telemetry.ex
defmodule ElixirSweBench.GitHub.Telemetry do
  @moduledoc """
  Telemetry events for GitHub API integration monitoring.
  """
  
  def setup do
    :telemetry.attach_many(
      "github-api-handler",
      [
        [:elixir_swe_bench, :github, :api_request, :start],
        [:elixir_swe_bench, :github, :api_request, :stop],
        [:elixir_swe_bench, :github, :rate_limit, :hit],
        [:elixir_swe_bench, :github, :cache, :hit],
        [:elixir_swe_bench, :github, :cache, :miss]
      ],
      &handle_event/4,
      []
    )
  end
  
  def handle_event([:elixir_swe_bench, :github, :api_request, :stop], measurements, metadata, _config) do
    Logger.info("GitHub API request completed", [
      method: metadata.method,
      url: metadata.url,
      duration: measurements.duration,
      status: metadata.status
    ])
  end
  
  # Additional event handlers...
end
```

## Success Metrics

### Technical Metrics
- API request success rate: >99.5%
- Average response time: <2 seconds
- Rate limit compliance: 100%
- Test coverage: >90%
- Data consistency: 100% (no duplicates)

### Functional Metrics
- Repository analysis accuracy: >95%
- Issue-PR relationship detection: >98%
- Task instance generation success: >90%
- Elixir-specific pattern recognition: >85%

### Performance Metrics
- Repository analysis throughput: >10 repos/hour
- Issue collection efficiency: >100 issues/minute
- Database query performance: <100ms average
- Memory usage: <512MB for typical workload

## Risk Mitigation

### Technical Risks
1. **GitHub API Rate Limiting**: Implement intelligent backoff, multiple token rotation
2. **Large Repository Analysis**: Streaming processing, paginated queries, timeout handling
3. **Database Performance**: Strategic indexing, query optimization, connection pooling
4. **Memory Usage**: Lazy evaluation, streaming, garbage collection monitoring

### Operational Risks
1. **GitHub API Changes**: Version pinning, backward compatibility, automated testing
2. **Data Quality**: Validation pipelines, manual review processes, quality scoring
3. **Scalability**: Horizontal scaling design, caching strategies, async processing

## Conclusion

This comprehensive implementation plan provides a robust foundation for GitHub API integration in the SWE-bench-Elixir project. The approach emphasizes:

- **Modern Technology Stack**: Leveraging Req for HTTP, Hammer for rate limiting, and UUID v7 for performance
- **Elixir-Specific Features**: Umbrella project detection, Hex.pm integration, and BEAM-specific patterns  
- **Production Readiness**: Comprehensive testing, monitoring, error handling, and scalability considerations
- **Data Quality**: Deduplication, validation, and quality scoring mechanisms
- **Performance Optimization**: Strategic indexing, caching, and streaming processing

The implementation will provide a solid foundation for collecting high-quality Elixir repository data while respecting API limits and maintaining system reliability.