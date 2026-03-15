# Roblox_Paintball_Test

# Claude Instructions

## Language Selection
Select the most appropriate coding language(s) for each task. Ensure all languages used in a project interact well with each other.

## UI Development
Every time the UI changes in form or function, provide a localhost link so the app can be previewed and tested or visualized.

---

## Development Workflow: BMAD + Supervisor Architecture

### Core Philosophy
- Prefer simplicity. Handle small/straightforward tasks directly.
- Use structured BMAD reasoning for complex work (multi-file, architectural, debugging cycles).
- Avoid unnecessary agent overhead.
- Always optimize for: clarity, speed, correctness, minimal token usage.

### BMAD Workflow

**Phase 1 — BREAK (Planning)**
- Interpret the request, decompose into tasks, identify dependencies, risks, edge cases, required files/modules.

**Phase 2 — MAP (Architecture)**
- Design before coding: architecture, frameworks, module boundaries, data flow, API interfaces, folder structure.

**Phase 3 — ACT (Implementation)**
- Write code incrementally, minimal diffs, readable, no unnecessary abstractions.

**Phase 4 — DEBUG (Review)**
- Review logic, check edge cases, identify bugs, suggest improvements and tests.

### When to Use BMAD

| Task Size | Phases Used |
|-----------|-------------|
| Simple (small edit, explanation, quick fix) | Respond directly — skip BMAD |
| Medium | Break → Act → Debug |
| Complex (new feature, integration, architecture) | Break → Map → Act → Debug |

### Internal Role Model
Claude internally simulates these roles (not separate agents unless needed):
- **Supervisor** — orchestrates phases
- **Planner** — Break phase
- **Architect** — Map phase
- **Builder** — Act phase
- **Reviewer** — Debug phase

### Development Principles
1. Think before coding
2. Prefer minimal changes
3. Match existing project conventions
4. Explain important architectural decisions
5. Validate unclear assumptions
6. Prefer clarity over cleverness

---

## Git Setup

### Branch Strategy
- Feature branches roll up to `dev`; `dev` rolls up to `main`
- At the start of every session, check existing branches
- If only `main` exists (new project), automatically create a `dev` branch and switch to it
- All new work branches off `dev`, never directly off `main`


