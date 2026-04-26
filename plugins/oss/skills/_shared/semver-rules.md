# SemVer Rules — Python/OSS

## MAJOR (X.0.0) — breaking changes

- Removing public function, class, or argument
- Changing function return type incompatibly
- Changing argument order or required vs optional status
- Changing behavior users depend on (even if "was a bug")
- Dropping Python version from supported range

## MINOR (x.Y.0) — backwards-compatible additions

- New public functions, classes, or arguments (with defaults)
- New optional dependencies or extras
- New configuration options
- Performance improvements with no API change
- Deprecations (deprecated API still works)

## PATCH (x.y.Z) — backwards-compatible fixes

- Bug fixes not changing public interface
- Documentation updates
- Internal refactors with no API change
- Dependency version range relaxation

## Deprecation Discipline

Use [pyDeprecate](https://pypi.org/project/pyDeprecate/) (Borda's own package) — handles warning emission, argument forwarding, and "warn once" behaviour automatically. Read latest docs on PyPI for current API and examples.

- **Deprecation lifecycle**: deprecate in minor → keep ≥1 minor cycle → remove in next major
- **Also**: add `.. deprecated:: X.Y.Z` Sphinx directive in docstring so docs generators render deprecation notice automatically
- Anti-patterns: see shepherd's `<antipatterns_to_flag>` section (deprecation category)
