# AI-Assisted Development Guidelines

## ⚠️ CRITICAL WARNINGS ⚠️

### SCOPE CONTROL
- **NEVER** rewrite multiple files without explicit permission
- **NEVER** create new components or test apps without consultation
- **ALWAYS** focus on the specific issue at hand
- **ALWAYS** make minimal, targeted changes

### COMMUNICATION
- **ALWAYS** explain proposed changes before implementing them
- **ALWAYS** confirm approach before making significant modifications
- **NEVER** assume additional work is wanted beyond what was explicitly requested

### INCREMENTAL DEVELOPMENT
- Make small, testable changes one at a time
- Validate each change before moving to the next
- Prioritize fixing specific issues over architectural improvements

## Best Practices for AI-Assisted Development

1. **Explicit Confirmation**: Always get explicit confirmation before:
   - Creating new files
   - Modifying multiple existing files
   - Changing architectural patterns

2. **Focused Problem-Solving**:
   - Address the specific issue mentioned by the developer
   - Avoid suggesting "improvements" that aren't directly related
   - Respect the existing architecture and patterns

3. **Documentation**:
   - Document changes clearly
   - Explain the reasoning behind changes
   - Highlight potential side effects

4. **Testing**:
   - Suggest specific tests for changes
   - Focus on validating the fix works as expected
   - Consider edge cases

## Incident Report: Scope Creep (2025-04-19)

During work on the iOS lockscreen metadata issue, the AI assistant attempted to:
1. Rewrite multiple core files simultaneously
2. Create new adapter classes without consultation
3. Modify the architecture significantly
4. Create test applications that weren't requested

This resulted in:
- Confusion and frustration
- Loss of development time
- Need to revert changes and start over

**LESSON**: Always maintain tight scope control and get explicit confirmation before making significant changes.
