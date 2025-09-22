# Support for xAI Responses API

This document outlines the end-to-end plan for evolving the library into a multi-provider client that supports both OpenAI and xAI Responses APIs.

## 1. Renaming & Packaging
- [x] Rename all modules to the `Responses` namespace and adjust directory structure to match (`lib/responses/*.ex`).
- [x] (Removed) Provide a compatibility layer (`OpenAI.Responses`) that delegates to the new modules and emits deprecation warnings; mark for removal in a future major release.
- [x] Update `mix.exs` project module, application atom (`:responses`), metadata (name, description, links), and any config references that currently mention `openai_responses`.
- [x] Migrate runtime configuration keys to `config :responses, ...` while still reading legacy keys for backward compatibility, logging a warning when used.
- [x] Run formatter and compilation to confirm the rename is complete and no stale aliases remain.

## 2. Provider Abstraction Core
- [x] Implement lightweight provider registry (`Responses.Provider`, `Responses.Provider.OpenAI`, `Responses.Provider.XAI`) exposing base URL, credential sources, and warning metadata.
- [x] Resolve providers by model identifier (`provider:model` or heuristic prefixes) without maintaining alias maps or defaults.
- [x] Refactor request/streaming/cost helpers to derive base URL, credentials, and pricing via the resolved provider; responses carry provider info for downstream consumers.
- [x] Emit provider-specific warnings (e.g., xAI `instructions`) while forwarding requests unchanged.
- [ ] Document supported prefixes, example usage, and guidance for extending the provider heuristics when new models appear.

## 3. Model Routing & Discovery
- [x] Route explicit `provider:model` identifiers directly to the chosen provider without additional aliasing.
- [x] Support prefix-based provider inference (`gpt-*`, `o1*`, `o3*`, `o4-mini*` → OpenAI; `grok-*` → xAI) and ensure follow-up calls reuse the resolved provider.
- [ ] Document the identifier rules and add regression tests covering both prefixed and inferred models.
- [ ] Revisit `Responses.list_models/1` if/when we need a combined provider listing; currently remains OpenAI-specific.

## 4. Capability Validation & Feedback
- [x] Emit provider-specific warnings for unsupported options (e.g., `instructions` with xAI) while still forwarding the request.
- [ ] Decide on additional feature warnings or an opt-out flag, then document the trade-offs.
- [ ] Add regression tests covering warnings for provider-incompatible options.

## 5. Authentication & Configuration
- [x] Support provider-specific credentials via config/env lookup with clear errors when unset; base URL overrides are independent per provider.
- [ ] Document configuration patterns for mixed-provider usage and migration from the single-provider setup.

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
