# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
