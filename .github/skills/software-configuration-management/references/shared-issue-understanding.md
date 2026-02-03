# Shared Issue Understanding

**Precondition**: Issue exists and is assigned. This is the first task in the implementation workflow.

This segment covers the initial assessment and approval phase of the implementation workflow.

## Step 1: Issue Assessment & Approval
- **Objective**: Establish a shared understanding of scope, dependencies, and blockers before editing any git-tracked files.
- **Activities**:
  - Review the issue description, comments, and attachments.
  - Assess technical impact, dependencies, and required configuration changes.
  - Identify **high-level show stoppers** that would prevent the task from progressing immediately (e.g., missing remote test infrastructure, unavailable SSH servers, or blocker secrets).
  - Document the analysis and proposed mitigation in the issue comments.
  - Ask for and obtain formal reviewer approval before touching any configuration controlled item.
- **Validation**: Approval comment or explicit sign-off is present in the GitHub issue conversation. No git changes until this approval exists.
- **Prohibition**: Even with formal approval, proceeding is prohibited if high-level show stoppers remain identified. The situation can only be resolved by a revised assessment (e.g., necessary fixtures have been implemented).