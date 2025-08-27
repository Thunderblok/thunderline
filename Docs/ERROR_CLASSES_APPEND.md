## Parser Error Classes (Incremental Addendum)

| Code | Class | HTTP Mapping | Description | Mitigation |
|------|-------|--------------|-------------|------------|
| E-PARSE-RULE-001 | parse.rule.syntax | 400 | CA rule line failed grammar parse | Surface first error segment, suggest canonical form B3/S23 rate=30Hz |
| E-PARSE-SPEC-001 | parse.spec.syntax | 400 | Workflow spec failed grammar parse | Provide failing line number & remaining text snippet |
| E-PARSE-SPEC-002 | parse.spec.unknown_after | 422 | after= references undeclared node | Ensure topological order; reorder or declare parent first |

Add to main ERROR_CLASSES.md on next consolidation sweep.