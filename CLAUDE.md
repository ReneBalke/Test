# CLAUDE.md - AI Assistant Development Guide

**Repository**: ReneBalke/Test
**Last Updated**: 2026-01-23
**Status**: New/Empty Repository

---

## Table of Contents

1. [Repository Overview](#repository-overview)
2. [Project Structure](#project-structure)
3. [Development Workflows](#development-workflows)
4. [Coding Conventions](#coding-conventions)
5. [Git Practices](#git-practices)
6. [Testing Guidelines](#testing-guidelines)
7. [Documentation Standards](#documentation-standards)
8. [AI Assistant Guidelines](#ai-assistant-guidelines)

---

## Repository Overview

### Current State
This is a newly initialized repository with no existing codebase. The repository is a blank slate ready for development.

### Repository Information
- **Owner**: ReneBalke
- **Repository Name**: Test
- **Git Remote**: `http://local_proxy@127.0.0.1:21281/git/ReneBalke/Test`
- **Primary Branch**: TBD (to be established with first commit)
- **Current Working Branch**: `claude/claude-md-mkqpfbdsim919rph-2Rb70`

### Purpose
*To be defined as project develops*

---

## Project Structure

### Expected Directory Layout
As the project grows, maintain a clear directory structure. Common patterns include:

```
/
├── src/           # Source code
├── tests/         # Test files
├── docs/          # Documentation
├── config/        # Configuration files
├── scripts/       # Build and utility scripts
├── .github/       # GitHub workflows and templates
├── README.md      # Project documentation
├── CLAUDE.md      # This file - AI assistant guide
└── LICENSE        # License information
```

### Current Structure
```
/
├── .git/          # Git repository metadata
└── CLAUDE.md      # This file
```

**Note**: Update this section as directories and files are added to the repository.

---

## Development Workflows

### Branch Strategy

**Feature Development**:
- AI assistants work on branches following the pattern: `claude/claude-md-*`
- Branch names must start with `claude/` and end with matching session ID
- Always develop on the designated branch provided in task context
- Never push to unspecified branches without explicit permission

**Branch Operations**:
```bash
# Create and switch to feature branch
git checkout -b claude/feature-name-sessionid

# Develop and commit changes
git add .
git commit -m "Clear, descriptive message"

# Push to remote (with retry logic for network errors)
git push -u origin claude/feature-name-sessionid
```

### Git Push Protocol
- Always use `git push -u origin <branch-name>`
- Branch must start with 'claude/' and end with matching session ID
- Retry logic: If push fails due to network errors, retry up to 4 times with exponential backoff (2s, 4s, 8s, 16s)
- Push failures with 403 errors indicate branch name mismatch

### Git Fetch/Pull Protocol
- Prefer specific branch fetching: `git fetch origin <branch-name>`
- For pulls: `git pull origin <branch-name>`
- Apply same retry logic as push operations for network failures

---

## Coding Conventions

### General Principles
*To be established based on chosen technology stack*

**Key Guidelines**:
1. **Consistency**: Follow existing code patterns in the repository
2. **Readability**: Write self-documenting code; comments only where logic isn't self-evident
3. **Simplicity**: Avoid over-engineering; implement only what's requested
4. **Security**: Never introduce vulnerabilities (XSS, SQL injection, command injection, etc.)

### Code Style
*To be defined when programming language is chosen*

### Naming Conventions
*To be defined when programming language is chosen*

### File Organization
*To be defined as project structure emerges*

---

## Git Practices

### Commit Messages

**Format**:
```
<type>: <subject>

<body (optional)>

<footer (optional - include session URL)>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks
- `style`: Formatting changes

**Example**:
```
feat: add user authentication system

Implement JWT-based authentication with login and registration endpoints.
Includes password hashing and token validation middleware.

https://claude.ai/code/session_XXXXX
```

### Commit Best Practices

1. **Read Before Modifying**: Always read files before proposing changes
2. **Atomic Commits**: Each commit should represent a single logical change
3. **Descriptive Messages**: Focus on "why" rather than "what"
4. **Never Skip Hooks**: Don't use --no-verify or --no-gpg-sign unless explicitly requested
5. **Never Force Push**: Especially to main/master branches
6. **Stage Specific Files**: Prefer `git add <file>` over `git add -A` or `git add .`
7. **Avoid Sensitive Data**: Never commit .env files, credentials, or secrets

### Git Safety Protocol

**NEVER**:
- Update git config without permission
- Run destructive commands (push --force, reset --hard, checkout ., restore ., clean -f, branch -D) unless explicitly requested
- Skip hooks
- Force push to main/master branches
- Use interactive flags (-i) with git commands
- Commit when not explicitly asked

**ALWAYS**:
- Create new commits rather than amending (unless explicitly requested)
- Fix and create new commits when pre-commit hooks fail
- Verify git status after operations

---

## Testing Guidelines

### Testing Strategy
*To be established when testing framework is chosen*

**Principles**:
1. Write tests for new features
2. Update tests when modifying existing functionality
3. Ensure all tests pass before committing
4. Maintain high test coverage for critical paths

### Test Organization
*To be defined as test suite develops*

### Running Tests
*To be documented when test framework is implemented*

---

## Documentation Standards

### Code Documentation
- Add comments only where logic isn't self-evident
- Keep documentation close to the code it describes
- Update documentation when code changes

### Project Documentation
- **README.md**: Project overview, setup instructions, usage examples
- **CLAUDE.md**: This file - AI assistant development guide
- **API Documentation**: To be added if API is developed
- **Architecture Docs**: To be added as system complexity grows

### Documentation Maintenance
- Update CLAUDE.md when project structure or conventions change
- Keep README.md current with setup and usage instructions
- Document breaking changes and migration paths

---

## AI Assistant Guidelines

### Primary Responsibilities

1. **Understand Before Acting**
   - Read existing files before modifying
   - Explore codebase structure before making changes
   - Ask for clarification when requirements are ambiguous

2. **Follow Conventions**
   - Adhere to established coding standards
   - Match existing code style and patterns
   - Respect project architecture decisions

3. **Task Management**
   - Use TodoWrite tool for multi-step tasks
   - Break complex tasks into manageable steps
   - Mark tasks as completed immediately after finishing
   - Keep only one task in_progress at a time

4. **Code Quality**
   - Avoid over-engineering
   - Don't add unrequested features or refactoring
   - Keep solutions simple and focused
   - Validate only at system boundaries
   - Trust internal code and framework guarantees

5. **Security First**
   - Never introduce security vulnerabilities
   - Validate and sanitize user input
   - Follow security best practices (OWASP Top 10)
   - Immediately fix any insecure code discovered

### Tool Usage Best Practices

**File Operations**:
- Use `Read` for reading files (not `cat`)
- Use `Edit` for modifying files (not `sed/awk`)
- Use `Write` for creating new files (not `echo` redirection)
- Use `Glob` for finding files by pattern (not `find`)
- Use `Grep` for searching file contents (not `grep` command)

**Task Exploration**:
- Use `Task` tool with `subagent_type=Explore` for codebase exploration
- Use specialized agents for complex, multi-step operations
- Run independent tool calls in parallel when possible

**Communication**:
- Output text directly to communicate with users
- Never use `echo` or code comments for user communication
- Keep responses concise and technically accurate
- Avoid emojis unless explicitly requested

### Workflow for New Features

1. **Planning Phase**
   - Create TodoWrite plan for multi-step tasks
   - Explore existing codebase for related functionality
   - Identify files that need modification

2. **Implementation Phase**
   - Read all relevant files before modifying
   - Make focused, minimal changes
   - Test changes incrementally
   - Mark todos as completed as you progress

3. **Verification Phase**
   - Run tests if they exist
   - Verify changes work as expected
   - Check for introduced vulnerabilities
   - Review for code quality

4. **Commit Phase**
   - Stage specific files that changed
   - Write clear, descriptive commit message
   - Include session URL in commit message
   - Verify commit success with git status

5. **Push Phase**
   - Push to the designated branch only
   - Use retry logic for network failures
   - Verify push success

### Workflow for Bug Fixes

1. **Investigation**
   - Read relevant files to understand the bug
   - Identify root cause
   - Plan minimal fix

2. **Fix Implementation**
   - Make targeted changes only
   - Don't refactor surrounding code
   - Preserve existing behavior except for the bug

3. **Verification**
   - Test that bug is fixed
   - Ensure no regressions introduced
   - Run test suite if available

4. **Commit and Push**
   - Follow standard commit workflow
   - Reference bug/issue in commit message

### What NOT to Do

1. **Over-Engineering**
   - Don't add features beyond what's requested
   - Don't create abstractions for one-time operations
   - Don't add error handling for impossible scenarios
   - Don't design for hypothetical future requirements

2. **Unnecessary Changes**
   - Don't add docstrings to unchanged code
   - Don't refactor code that works
   - Don't add type annotations to existing code
   - Don't create "improvement" commits without request

3. **Backwards-Compatibility Hacks**
   - Don't rename unused variables with `_` prefix
   - Don't re-export types just to keep old imports
   - Don't add `// removed` comments
   - Delete unused code completely

4. **Inappropriate Tool Usage**
   - Don't use bash for file operations
   - Don't use echo to communicate with users
   - Don't run grep/find commands directly
   - Don't create files unnecessarily

### Code References

When referencing code in responses, use the pattern:
```
file_path:line_number
```

Example: "The authentication logic is in `src/auth/login.js:45`"

### Error Handling

**When Errors Occur**:
1. Read error messages carefully
2. Investigate root cause before attempting fix
3. Fix the underlying issue, don't mask symptoms
4. Test that fix resolves the error
5. Don't mark tasks as completed if errors persist

**When Blocked**:
1. Clearly communicate the blocker to the user
2. Create a new todo for what needs resolution
3. Keep original task as in_progress, not completed
4. Ask for guidance or clarification if needed

---

## Maintaining This Document

### When to Update CLAUDE.md

This document should be updated when:
- Project structure changes significantly
- New coding conventions are established
- Development workflow changes
- New tools or frameworks are adopted
- Testing strategy is implemented
- Build or deployment processes are defined
- New patterns or best practices emerge

### How to Update

1. Read the current CLAUDE.md file
2. Identify sections that need updates
3. Make precise, focused updates
4. Keep formatting and structure consistent
5. Update the "Last Updated" date at the top
6. Commit with message: `docs: update CLAUDE.md`

### Version History

- **2026-01-23**: Initial creation - Empty repository baseline

---

## Quick Reference

### Essential Commands

```bash
# Check repository status
git status

# Create feature branch
git checkout -b claude/feature-name-sessionid

# Stage specific files
git add path/to/file

# Commit with message
git commit -m "type: description"

# Push to remote
git push -u origin claude/feature-name-sessionid

# View recent commits
git log --oneline -10
```

### Common Task Patterns

**Adding a New Feature**:
1. Read existing related code
2. Plan with TodoWrite if multi-step
3. Implement minimal solution
4. Test thoroughly
5. Commit and push to designated branch

**Fixing a Bug**:
1. Reproduce and understand bug
2. Identify root cause
3. Make targeted fix
4. Verify fix works
5. Commit and push

**Exploring Codebase**:
1. Use Task tool with Explore agent
2. Search with Grep for keywords
3. Find files with Glob patterns
4. Read relevant files with Read tool

---

## Notes for Future Development

As this repository grows, consider adding:
- CI/CD pipeline configuration
- Pre-commit hooks for code quality
- Automated testing setup
- Code linting and formatting rules
- Dependency management strategy
- Deployment documentation
- Performance monitoring
- Security scanning

Keep this document updated to reflect the evolving nature of the project.

---

**Remember**: This document exists to help AI assistants work effectively on this codebase. Keep it current, comprehensive, and practical.
