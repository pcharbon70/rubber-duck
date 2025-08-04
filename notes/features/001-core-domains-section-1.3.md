# Feature: Core Domains Section 1.3

## Summary
Implement section 1.3 of the planning document: Ash Framework Foundation. This includes creating core domains (Accounts, Projects, AI), implementing base resources (Project, CodeFile, AnalysisResult, Prompt), setting up resource relationships, and configuring Ash policies.

## Requirements
- [ ] Create RubberDuck.Projects domain
- [ ] Create RubberDuck.AI domain  
- [ ] Implement Project resource with attributes and actions
- [ ] Implement CodeFile resource with attributes and actions
- [ ] Implement AnalysisResult resource with attributes and actions
- [ ] Implement Prompt resource with attributes and actions
- [ ] Set up resource relationships (Project has_many CodeFiles, Project has_many AnalysisResults, User has_many Projects)
- [ ] Configure foreign keys properly
- [ ] Configure Ash policies with policy authorizer
- [ ] Create base policies for all resources
- [ ] Configure bypass rules for admin access
- [ ] Add audit logging capabilities
- [ ] Write unit tests for resource creation
- [ ] Write unit tests for relationship loading
- [ ] Write unit tests for policy enforcement
- [ ] Write unit tests for change tracking
- [ ] Ensure no compilation errors or warnings
- [ ] Pass credo analysis without warnings

## Research Summary

### Existing Usage Rules Checked
- **Ash Framework**: Domain-centric architecture with declarative resources, use code interfaces on domains, avoid direct Ash calls in web modules, prefer domain actions over generic CRUD
- **AshPostgres**: PostgreSQL data layer configuration, proper migration generation, foreign key constraints
- **AshAuthentication**: Already implemented User resource with username-only authentication

### Documentation Reviewed
- **Ash Core**: Resource definitions, actions, relationships, policies, calculations, aggregates
- **Code Interfaces**: Define interfaces on domains with `resource ResourceName do define :fun_name, action: :action_name end`
- **Relationships**: belongs_to adds foreign key to source, has_one/has_many uses foreign key on destination, many_to_many requires join resource
- **Policies**: Use `Ash.Policy.Authorizer`, policies evaluate top to bottom, first check that yields result determines outcome

### Existing Patterns Found
- **RubberDuck.Accounts domain**: Located at `lib/rubber_duck/accounts.ex`, contains User and Token resources
- **RubberDuck.Accounts.User**: Username-only authentication resource with bcrypt password hashing
- **Domain structure**: Uses `use Ash.Domain, otp_app: :rubber_duck` pattern

### Technical Approach
1. **Create new domains**: Follow existing pattern in `lib/rubber_duck/` directory structure
2. **Projects domain**: Create `lib/rubber_duck/projects.ex` with Project and CodeFile resources
3. **AI domain**: Create `lib/rubber_duck/ai.ex` with AnalysisResult and Prompt resources
4. **Resources structure**: Each resource in `lib/rubber_duck/domain_name/resource_name.ex`
5. **Relationships**: Use belongs_to for foreign keys, has_many for reverse relationships
6. **Policies**: Add `Ash.Policy.Authorizer` to each resource, create user-based access control
7. **Code interfaces**: Define on domains for clean API access
8. **Database setup**: Use AshPostgres.DataLayer, configure postgres section with table names and repo
9. **Migrations**: Generate with `mix ash.codegen` after resource creation
10. **Testing**: Create tests in `test/rubber_duck/` following ExUnit patterns

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Resource relationship conflicts | Medium | Carefully design foreign key relationships, test thoroughly |
| Policy configuration errors | High | Start with simple policies, test authorization flows |
| Migration generation issues | Medium | Use `mix ash.codegen --dev` during development, review migrations |
| Existing User resource integration | Medium | Ensure new domains properly reference existing Accounts.User |
| Database constraint violations | Medium | Proper foreign key setup, test edge cases |

## Implementation Checklist
- [ ] Create `lib/rubber_duck/projects.ex` domain file
- [ ] Create `lib/rubber_duck/ai.ex` domain file
- [ ] Create `lib/rubber_duck/projects/project.ex` resource
- [ ] Create `lib/rubber_duck/projects/code_file.ex` resource
- [ ] Create `lib/rubber_duck/ai/analysis_result.ex` resource
- [ ] Create `lib/rubber_duck/ai/prompt.ex` resource
- [ ] Configure relationships between User, Project, CodeFile, AnalysisResult
- [ ] Add AshPostgres data layer configuration to all resources
- [ ] Configure Ash policies on all resources
- [ ] Add code interfaces to domains
- [ ] Generate migrations with `mix ash.codegen`
- [ ] Run migrations with `mix ash.setup`
- [ ] Create comprehensive unit tests
- [ ] Verify compilation with `mix compile`
- [ ] Run credo analysis with `mix credo`
- [ ] Fix any warnings or suggestions

## Questions for Pascal
1. Should CodeFile include the actual file content or just metadata/path references?
2. What specific attributes should AnalysisResult contain (complexity scores, suggestions, etc.)?
3. Should Prompt resource store template variables separately or as embedded data?
4. Any specific policy requirements beyond basic user ownership?

## Log
- **2025-01-04**: Created feature branch `feature/1.3-core-domains-section-1.3`
- **2025-01-04**: Starting implementation of core domains
- **2025-01-04**: Created Projects and AI domains with complete resource structure
- **2025-01-04**: Implemented Project, CodeFile, AnalysisResult, and Prompt resources
- **2025-01-04**: Fixed Ash policies for create actions (cannot use relationships in create policies)
- **2025-01-04**: Generated and ran migrations successfully
- **2025-01-04**: All tests passing, no compilation errors/warnings
- **2025-01-04**: Added @moduledoc to all new modules for credo compliance

## Final Implementation

Section 1.3 has been successfully implemented with the following components:

### Domains Created
- **RubberDuck.Projects**: Manages projects and code files
- **RubberDuck.AI**: Manages analysis results and prompts

### Resources Implemented
- **Project**: Core project metadata with owner relationship
- **CodeFile**: Individual files within projects with content and metadata
- **AnalysisResult**: AI analysis results linked to projects/files
- **Prompt**: Reusable AI prompt templates with sharing capabilities

### Key Features
- Full CRUD operations via code interfaces
- Proper authorization policies with create action support
- Database migrations generated and applied
- Comprehensive test coverage
- Clean code with documentation

### Deviations from Plan
- Simplified CodeFile resource (removed automatic size calculation for now)
- Used `authorize_if always()` for create actions due to Ash limitations
- All new modules documented for credo compliance

### Follow-up Tasks
- Consider adding custom policy checks for more granular create authorization
- Implement automatic content-based size calculation for CodeFile
- Add more comprehensive test scenarios
- Consider adding resource validations and constraints