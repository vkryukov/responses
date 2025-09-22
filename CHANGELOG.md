# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-09-22
### Added
- Introduced the `Responses.Provider` registry with `Responses.Provider.OpenAI` and `Responses.Provider.XAI` implementations for credential lookup, model routing, and provider-specific warnings.
- Added first-party support for xAI models including pricing data, telemetry metadata, and request/streaming tests that validate multi-provider flows.
- Exposed a `provider_warnings` option (and `:provider_warning_mode` config) to control whether unsupported option warnings are emitted per provider.
- Documented multi-provider configuration patterns and added Livebook/tutorial coverage for running responses against xAI.

### Changed
- `Responses.list_models/1` now requires a provider atom and `list_models/2` applies provider-scoped filtering while returning the raw upstream payload.
- Cost calculation automatically scopes to the resolved provider and surfaces descriptive errors when pricing metadata is missing.
- Telemetry events include provider identifiers so downstream instrumentation can differentiate usage per provider.

### Migration Guide
1. Update your dependency entry to `{:responses, "~> 0.1.0"}`.
2. Configure provider-specific credentials with `config :responses, :openai_api_key` and/or `:xai_api_key` (or the matching environment variables).
3. When requesting models, supply explicit provider hints (`model: "provider:model"`) or rely on the documented prefixes (`gpt-*`, `o1*`, `o3*`, `o4-mini*` map to OpenAI; `grok-*` maps to xAI).
4. Review telemetry consumers for the new provider metadata and adjust alerting or dashboards as needed.

## [0.0.1] - 2024-09-21
### Changed
- Renamed the library namespace from `OpenAI.Responses` to `Responses`.
- Updated the OTP application name to `:responses` and refreshed package metadata.
- Adjusted configuration keys and documentation snippets to use the new namespace.

### Migration Guide
1. Update your dependency entry to `{:responses, "~> 0.0.1"}`.
2. Replace module references from `OpenAI.Responses` to `Responses`.
3. Update application configuration to use `config :responses, :openai_api_key, "your-key"` (legacy keys continue to work with warnings).
4. Review `CHANGELOG_OLD.md` for historical notes from earlier releases.
