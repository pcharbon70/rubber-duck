# RAG Library Concepts Guide

A comprehensive guide to understanding the concepts, components, and interactions within the RAG (Retrieval Augmented Generation) library.

## Table of Contents
1. [Introduction to RAG](#introduction-to-rag)
2. [Core Architecture](#core-architecture)
3. [The Generation Pipeline](#the-generation-pipeline)
4. [Component Deep Dive](#component-deep-dive)
5. [AI Provider System](#ai-provider-system)
6. [Data Flow and Interactions](#data-flow-and-interactions)
7. [Code Generation and Setup](#code-generation-and-setup)
8. [Monitoring and Telemetry](#monitoring-and-telemetry)
9. [Usage Patterns](#usage-patterns)

## Introduction to RAG

RAG (Retrieval Augmented Generation) is a technique that enhances language model capabilities by combining retrieval-based and generative approaches. This library addresses three core problems with traditional language models:

- **Knowledge Cutoff**: Limited to training data up to a specific point in time
- **Hallucinations**: Generation of confident but incorrect information
- **Contextual Relevance**: Difficulty providing contextually relevant responses

RAG solves these by retrieving relevant information from external knowledge sources before generating responses, ensuring more accurate and current outputs.

## Core Architecture

The RAG library is built around a **pipeline-based architecture** with several key design principles:

### 1. Pipeline-Based Processing
The core data structure is the `Generation` struct, which flows through a series of transformation functions:

```
Query → Embedding → Retrieval → Context Building → Prompt Building → Response Generation
```

### 2. Immutable Data Flow
Each stage of the pipeline creates a new version of the `Generation` struct rather than modifying it in place, following functional programming principles.

### 3. Error Handling with Halt Mechanism
The pipeline includes a `halted?` flag that stops processing when errors occur, preventing cascading failures.

### 4. Pluggable Provider System
AI capabilities (embeddings and text generation) are abstracted through a behavior pattern, allowing different providers to be swapped without changing core logic.

## The Generation Pipeline

### Generation Struct

The `Generation` struct is the central data structure that carries information through the pipeline:

```elixir
%Generation{
  query: "user's question",                    # Original user query
  query_embedding: [0.1, 0.2, ...],          # Vector representation of query
  retrieval_results: %{                       # Results from various retrievers
    semantic_results: [...],
    fulltext_results: [...]
  },
  context: "relevant information...",          # Assembled context for prompt
  context_sources: ["source1.txt", ...],      # Sources of context information
  prompt: "formatted prompt...",               # Final prompt for LLM
  response: "generated answer",                # LLM response
  evaluations: %{                             # Evaluation results
    rag_triad: %{...},
    hallucination: false
  },
  halted?: false,                             # Error state flag
  errors: [],                                 # Collection of errors
  ref: reference                              # Optional reference for tracking
}
```

### Pipeline Stages

#### 1. **Query Processing**
- Input: User's natural language question
- Creates initial `Generation` struct with query

#### 2. **Embedding Generation**
- Converts the query into a vector representation
- Uses AI providers to generate embeddings
- Stores result in `query_embedding`

#### 3. **Retrieval**
- Multiple retrieval strategies can be employed:
  - **Semantic Search**: Uses embeddings to find similar content
  - **Full-text Search**: Traditional keyword-based search
  - **Hybrid Approaches**: Combines multiple retrieval methods
- Results stored in `retrieval_results` map with different keys

#### 4. **Result Fusion**
- **Reciprocal Rank Fusion (RRF)**: Combines multiple retrieval results
- **Deduplication**: Removes duplicate entries based on specified keys
- **Concatenation**: Simple combination of multiple result sets

#### 5. **Context Building**
- Assembles retrieved documents into coherent context
- Configurable context builder functions
- Sets `context` and `context_sources` fields

#### 6. **Prompt Building**
- Creates formatted prompt using query and context
- Template-based approach with customizable prompt builders
- Stores final prompt in `prompt` field

#### 7. **Response Generation**
- Passes prompt to language model
- Supports both streaming and non-streaming responses
- Stores result in `response` field

#### 8. **Evaluation (Optional)**
- **RAG Triad**: Evaluates context relevance, groundedness, and answer relevance
- **Hallucination Detection**: Checks if response is supported by context
- Results stored in `evaluations` map

## Component Deep Dive

### 1. Rag.Generation Module

**Purpose**: Core struct and pipeline management functions

**Key Functions**:
- `new/2`: Creates new Generation struct
- `put_*` functions: Immutable updates to struct fields
- `generate_response/3`: Orchestrates response generation with telemetry
- `build_context/3`, `build_prompt/3`: Pipeline stage orchestration
- `halt/1`, `add_error/2`: Error handling

**Pipeline Integration**: Central to all pipeline operations, provides the data structure and core transformation functions.

### 2. Rag.Embedding Module

**Purpose**: Vector embedding generation for text

**Key Functions**:
- `generate_embedding/2`: Single text to embedding (for queries)
- `generate_embedding/3`: Map-based embedding with configurable keys
- `generate_embeddings_batch/3`: Batch processing for efficiency

**Pipeline Integration**: 
- Converts user queries to vectors for semantic search
- Processes document chunks during ingestion
- Works with any AI provider implementing the embedding behavior

**Usage Patterns**:
```elixir
# Query embedding in pipeline
generation 
|> Embedding.generate_embedding(provider)

# Batch processing during ingestion
documents
|> Embedding.generate_embeddings_batch(provider, text_key: :content)
```

### 3. Rag.Retrieval Module

**Purpose**: Data retrieval and result processing

**Key Functions**:
- `retrieve/3`: Generic retrieval with custom functions
- `concatenate_retrieval_results/3`: Simple result combination
- `reciprocal_rank_fusion/4`: Advanced result fusion using RRF algorithm
- `deduplicate/3`: Remove duplicate entries

**Reciprocal Rank Fusion Algorithm**:
- Combines rankings from multiple retrieval systems
- Uses formula: `score = weight * length / (k + rank)` where k=60 (from original paper)
- Normalizes scores across different retrievers
- Fuses results with same identity keys

**Pipeline Integration**:
```elixir
generation
|> Retrieval.retrieve(:semantic, &semantic_search/1)
|> Retrieval.retrieve(:fulltext, &fulltext_search/1)
|> Retrieval.reciprocal_rank_fusion(%{semantic: 1, fulltext: 1}, :combined)
|> Retrieval.deduplicate(:combined, [:id])
```

### 4. Rag.Evaluation Module

**Purpose**: Quality assessment of RAG responses

**RAG Triad Evaluation**:
- **Context Relevance**: Is retrieved context relevant to query?
- **Groundedness**: Is response supported by context?
- **Answer Relevance**: Is answer relevant to query?
- Uses structured JSON schema for consistent evaluation
- Scores from 1-5 for each dimension

**Hallucination Detection**:
- Binary YES/NO classification
- Determines if response is supported by provided context
- Uses simple prompt-based approach

**Pipeline Integration**: Optional evaluation stage after response generation

### 5. Rag.Loading Module

**Purpose**: Data ingestion utilities

**Current Capabilities**:
- `load_file/1`: Reads file content from filesystem
- Extensible design for additional data sources

**Integration Pattern**: Used during document ingestion before chunking and embedding

## AI Provider System

### Provider Behavior

All AI providers implement the `Rag.Ai.Provider` behavior:

```elixir
@callback new(attrs :: map()) :: struct()
@callback generate_embeddings(provider, texts, opts) :: {:ok, list(embedding())} | {:error, any()}
@callback generate_text(provider, prompt, opts) :: {:ok, response()} | {:error, any()}
```

### Available Providers

#### 1. **OpenAI Provider** (`Rag.Ai.OpenAI`)
- **Capabilities**: Embeddings and text generation
- **Features**: Streaming support, configurable models and URLs
- **Configuration**: Requires API key, supports custom endpoints
- **Streaming**: Full Server-Sent Events (SSE) support with chunked processing

#### 2. **Cohere Provider** (`Rag.Ai.Cohere`)
- **Capabilities**: Embeddings and text generation
- **Features**: Specialized for search use cases, streaming support
- **Configuration**: API key required, uses Cohere v2 API
- **Specialty**: Optimized for search/retrieval scenarios

#### 3. **Ollama Provider** (`Rag.Ai.Ollama`)
- **Capabilities**: Local model inference
- **Features**: No API key required, runs models locally
- **Configuration**: Configurable localhost endpoints
- **Use Case**: Privacy-focused, offline capable deployments

#### 4. **Nx Provider** (`Rag.Ai.Nx`)
- **Capabilities**: Local inference using Elixir's Nx ecosystem
- **Features**: Fully local, uses Bumblebee models
- **Configuration**: Requires `Nx.Serving` instances
- **Integration**: Works with generated serving configurations

### Provider Selection Strategy

```elixir
# Cloud-based with API keys
openai_provider = Ai.OpenAI.new(%{
  embeddings_model: "text-embedding-3-small",
  text_model: "gpt-4o-mini",
  api_key: "sk-..."
})

# Local inference
nx_provider = Ai.Nx.new(%{
  embeddings_serving: Rag.EmbeddingServing,
  text_serving: Rag.LLMServing
})
```

## Data Flow and Interactions

### Typical RAG Flow

1. **Ingestion Phase** (Setup):
   ```
   Documents → Chunking → Embedding → Vector Store
   ```

2. **Query Phase** (Runtime):
   ```
   User Query → Query Embedding → Retrieval → Context Assembly → Prompt Creation → LLM → Response
   ```

### Component Interactions

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│   Loading   │───▶│   Embedding  │───▶│ Vector Store│
└─────────────┘    └──────────────┘    └─────────────┘
                                              │
┌─────────────┐    ┌──────────────┐          │
│ User Query  │───▶│   Embedding  │          │
└─────────────┘    └──────────────┘          │
                          │                  │
                          ▼                  ▼
                   ┌──────────────┐    ┌─────────────┐
                   │  Generation  │◀───│  Retrieval  │
                   │    Struct    │    └─────────────┘
                   └──────────────┘
                          │
                          ▼
                   ┌──────────────┐    ┌─────────────┐
                   │   Context    │───▶│   Prompt    │
                   │   Builder    │    │   Builder   │
                   └──────────────┘    └─────────────┘
                          │                  │
                          ▼                  ▼
                   ┌──────────────┐    ┌─────────────┐
                   │      LLM     │───▶│  Response   │
                   │   Provider   │    └─────────────┘
                   └──────────────┘
                          │
                          ▼
                   ┌──────────────┐
                   │  Evaluation  │
                   │  (Optional)  │
                   └──────────────┘
```

### Error Propagation

The pipeline includes robust error handling:

1. **Error Detection**: Each stage can detect and report errors
2. **Halt Mechanism**: `halted?` flag stops further processing
3. **Error Collection**: All errors collected in `errors` list
4. **Graceful Degradation**: Partial results preserved even with errors

## Code Generation and Setup

### Mix Tasks Overview

The library provides four Mix tasks for project setup and code generation:

#### 1. **`mix rag.install`** - Complete Setup
- **Purpose**: One-command setup for entire RAG system
- **Features**: 
  - Installs dependencies (text_chunker, bumblebee, exla)
  - Configures Nx backend
  - Sets up vector store (pgvector or chroma)
  - Composes other generation tasks
- **Usage**: `mix rag.install --vector-store pgvector`

#### 2. **`mix rag.gen_servings`** - AI Model Setup
- **Purpose**: Creates local AI model servings using Nx
- **Generated Components**:
  - Embedding serving (thenlper/gte-small model)
  - LLM serving (SmolLM2-135M-Instruct model)
  - Application children for serving processes
- **Configuration**: EXLA backend, batch processing, timeout settings

#### 3. **`mix rag.gen_rag_module`** - Core RAG Logic
- **Purpose**: Generates main RAG module with ingestion and query pipelines
- **Vector Store Variants**:
  - **PGVector**: Uses PostgreSQL with vector extensions, Ecto queries
  - **Chroma**: Uses Chroma vector database client
- **Generated Functions**:
  - `ingest/1`: Document processing pipeline
  - `query/1`: Question answering pipeline
  - Vector search implementations
  - Prompt templates

#### 4. **`mix rag.gen_eval`** - Evaluation Setup
- **Purpose**: Creates evaluation scripts and configuration
- **Features**:
  - Downloads public datasets for evaluation
  - Generates evaluation scripts using RAG Triad
  - OpenAI configuration for evaluation LLM
  - JSON output for analysis

### Generated Code Architecture

#### PGVector Implementation
```elixir
# Database schema with vector extension
schema "chunks" do
  field(:document, :string)
  field(:source, :string) 
  field(:chunk, :string)
  field(:embedding, Pgvector.Ecto.Vector)
end

# Hybrid retrieval: semantic + fulltext
|> Retrieval.retrieve(:semantic, &query_with_pgvector/1)
|> Retrieval.retrieve(:fulltext, &query_fulltext/1)
|> Retrieval.reciprocal_rank_fusion(%{semantic: 1, fulltext: 1}, :combined)
```

#### Chroma Implementation
```elixir
# Collection-based storage
{:ok, collection} = Chroma.Collection.get_or_create("rag", %{"hnsw:space" => "l2"})

# Batch insertion and querying
Chroma.Collection.add(collection, batch)
Chroma.Collection.query(collection, query_embeddings: [embedding])
```

## Monitoring and Telemetry

### Telemetry Events

The library emits comprehensive telemetry events for monitoring:

```elixir
# Embedding events
[:rag, :generate_embedding, :start | :stop | :exception]
[:rag, :generate_embeddings_batch, :start | :stop | :exception]

# Generation events  
[:rag, :generate_response, :start | :stop | :exception]

# Retrieval events
[:rag, :retrieve, :start | :stop | :exception]

# Evaluation events
[:rag, :detect_hallucination, :start | :stop | :exception]
[:rag, :evaluate_rag_triad, :start | :stop | :exception]
```

### Telemetry Metadata

Each event includes relevant metadata:
- **Start Events**: Include input parameters and configuration
- **Stop Events**: Include results and performance metrics
- **Exception Events**: Include error details and context

### Integration Pattern

```elixir
:telemetry.span([:rag, :generate_embedding], metadata, fn ->
  # Perform operation
  result = embedding_function.(texts)
  
  # Return result with updated metadata
  {result, %{metadata | result: result}}
end)
```

## Usage Patterns

### Basic RAG Pipeline

```elixir
# Setup provider
provider = Rag.Ai.Nx.new(%{
  embeddings_serving: Rag.EmbeddingServing,
  text_serving: Rag.LLMServing
})

# Process query
generation = 
  Generation.new("What is machine learning?")
  |> Embedding.generate_embedding(provider)
  |> Retrieval.retrieve(:docs, &search_documents/1)
  |> Generation.build_context(&build_context_from_docs/2)
  |> Generation.build_prompt(&create_qa_prompt/2)
  |> Generation.generate_response(provider)
```

### Advanced Multi-Retrieval

```elixir
generation
|> Retrieval.retrieve(:semantic, &semantic_search/1)
|> Retrieval.retrieve(:keyword, &keyword_search/1)  
|> Retrieval.retrieve(:recent, &time_based_search/1)
|> Retrieval.reciprocal_rank_fusion(%{
    semantic: 2,    # Higher weight
    keyword: 1,
    recent: 1
  }, :fused_results)
|> Retrieval.deduplicate(:fused_results, [:id, :source])
```

### Evaluation Pipeline

```elixir
# Generate response
generation = MyApp.Rag.query("How does photosynthesis work?")

# Evaluate quality
evaluation_provider = Rag.Ai.OpenAI.new(%{
  text_model: "gpt-4o-mini", 
  api_key: api_key
})

evaluated_generation = 
  generation
  |> Evaluation.evaluate_rag_triad(evaluation_provider)
  |> Evaluation.detect_hallucination(evaluation_provider)

# Extract scores
%{evaluations: %{
  rag_triad: %{
    "context_relevance_score" => context_score,
    "groundedness_score" => ground_score,
    "answer_relevance_score" => answer_score
  },
  hallucination: is_hallucination?
}} = evaluated_generation
```

### Error Handling

```elixir
case generation do
  %Generation{halted?: true, errors: errors} ->
    Logger.error("RAG pipeline failed: #{inspect(errors)}")
    {:error, :rag_failure}
    
  %Generation{response: response} ->
    {:ok, response}
end
```

### Streaming Responses

```elixir
# Enable streaming in provider
generation = 
  Generation.new(query)
  |> # ... pipeline stages
  |> Generation.generate_response(provider, stream: true)

# Handle stream
case generation.response do
  stream when is_function(stream) ->
    Enum.each(stream, &IO.write/1)
    
  text when is_binary(text) ->
    IO.puts(text)
end
```

This comprehensive guide covers all major concepts and interactions within the RAG library. The modular, pipeline-based architecture allows for flexible composition of different retrieval strategies, AI providers, and evaluation approaches while maintaining clean separation of concerns and robust error handling.