# Support for xAI Responses API

This document outlines the end-to-end plan for evolving the library into a multi-provider client that supports both OpenAI and xAI Responses APIs.

## 1. Renaming & Packaging
- Rename all modules to the `Responses` namespace and adjust directory structure to match (`lib/responses/*.ex`).
- Provide a compatibility layer (`OpenAI.Responses`) that delegates to the new modules and emits deprecation warnings; mark for removal in a future major release.
- Update `mix.exs` project module, application atom (`:responses`), metadata (name, description, links), and any config references that currently mention `openai_responses`.
- Migrate runtime configuration keys to `config :responses, ...` while still reading legacy keys for backward compatibility, logging a warning when used.
- Run formatter and compilation to confirm the rename is complete and no stale aliases remain.

## 2. Provider Abstraction Core
- Introduce a provider registry (`Responses.Provider`, `Responses.Provider.OpenAI`, `Responses.Provider.XAI`) encapsulating base URL, authentication keys, supported features, pricing, and model aliases.
- Refactor request helpers (`Responses.request/1`, streaming, cost calculators) to pull base URL, headers, and pricing from the resolved provider instead of hard-coded OpenAI values.
- Allow per-request provider overrides by storing provider metadata on the normalized request options and responses.
- Expose helper functions for querying supported providers and configuring defaults if needed.

## 3. Model Routing & Aliasing
- Parse model identifiers with optional prefixes (`openai:gpt-5`, `xai:grok-4`); when no prefix is provided, resolve using a per-provider alias map, prioritizing unique matches.
- Persist the resolved provider ID alongside the normalized model so downstream logic (requests, pricing, capabilities) can derive the provider without repeated parsing.
- Update `Responses.list_models/1` to optionally query all providers, include provider metadata in results, and respect provider filtering arguments.
- Ensure streaming, follow-up requests, and function-calling flows reuse the resolved provider so a conversation stays within the same provider unless explicitly switched.

## 4. Capability Validation & Feedback
- Encode provider-specific feature flags (e.g., supports `instructions`, `modalities`, tool calling) within the provider definitions.
- During option normalization, detect unsupported parameters for the chosen provider and emit descriptive warnings or errors guiding users toward supported options.
- Offer an override (opt-out) flag for teams that prefer permissive behavior, documenting the trade-offs.
- Add regression tests covering warnings/errors for provider-incompatible options (e.g., `instructions` with xAI).

## 5. Authentication & Configuration
- Support separate environment variables/config entries (`OPENAI_API_KEY`, `XAI_API_KEY`) and allow overriding base URLs for custom gateways.
- Update internal API key retrieval to accept a provider argument and look up the appropriate credentials with clear error messages when unset.
- Document configuration patterns for mixed-provider usage and migration from the legacy single-provider setup.

## 6. Pricing & Telemetry
- Extend `Responses.Pricing` to store per-provider token prices; ensure cost calculations select the correct provider and surface an error if pricing data is missing.
- Include provider metadata in telemetry/logging hooks so downstream systems can differentiate usage by provider.
- Add tests validating pricing for representative models across providers and guard against missing pricing entries.

## 7. Documentation & Tutorials
- Refresh the README introduction, examples, and badges to reflect multi-provider support and the new namespace.
- Update `tutorial.livemd`, `usage-rules.md`, and ExDoc guides with provider-prefixed model examples, capability caveats, and configuration walkthroughs.
- Insert CHANGELOG entries summarizing the rename, provider abstraction, and breaking changes; bump the version as appropriate.
- Review existing guides (e.g., `AGENTS.md`, `CLAUDE.md`) for assumptions tied to OpenAI and adjust references accordingly.

## 8. Testing & Release Readiness
- Update all unit and integration tests to use the new namespace and cover provider resolution, capability validation, and pricing behavior.
- Add mocked HTTP tests validating both OpenAI and xAI request flows, including streaming scenarios.
- Verify Credo, Dialyzer, formatter, and ExDoc outputs after the rename and provider abstraction changes.
- Prepare migration guidance in README/CHANGELOG detailing code changes required by downstream users and confirm package metadata (hex.pm, repository URL) matches the new project identity.
