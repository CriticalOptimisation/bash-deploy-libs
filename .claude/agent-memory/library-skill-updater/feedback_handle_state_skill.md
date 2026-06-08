---
name: handle-state skill structure conventions
description: Conventions for structuring the handle-state library skill, including token-routing helper documentation requirements
type: feedback
---

When writing or updating the handle-state library skill, follow these conventions:

1. Document `hs_extract_token` with all three call forms labeled Form 1/2/3 — they have distinct semantics and all three are used in canonical patterns.
2. Document both canonical entry-point patterns (read-write and read-only) as named sections with complete code blocks.
3. The old nameref pattern should be noted as still valid for simple cases but discouraged for public API functions.
4. Cross-reference issue #104 (nameref collision) as the motivation for the token-routing helpers.
5. The `--list-reserved` propagation machinery is an invariant of the public API — document it under Constraints, not as an optional feature.

**Why:** The three forms of `hs_extract_token` are easy to conflate; an LLM that only sees one form will produce incorrect entry-point code. The read-write vs read-only distinction determines which form to use.

**How to apply:** Every time the handle-state skill is updated, verify all three forms are present and the canonical patterns are complete and syntactically correct.
