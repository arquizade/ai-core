# Shared AI Core Rules

Vault root: ~/ai-core
Code lives in ~/Code. Link to repos by path. Never copy code into the vault except in coding/snippets/.

## Folders
- inbox/: raw captures. Do not sort them yourself unless asked.
- planning/: roadmap.md, weekly/ (one file per week), specs/ (feature specs written before building).
- coding/: architecture/, bugs/, snippets/, setup/.
- projects/: one index note per project, linking to its specs, bugs, and repo path.
- decisions/: one dated note per decision, with the reason.
- log/: monthly append-only file. Add entries at the end. Never edit or delete old entries.
- people/: collaborators and their preferences.
- templates/: copy these when creating a new note.
- archive/: finished projects and old weekly plans.

## Note header (required on every note)
Start every note with:

date: YYYY-MM-DD
model: your model name
project: project name or none
type: spec | bug | decision | log | plan | snippet | setup | architecture | project | person

## Write rules
1. Read the relevant project note and recent log entries before you answer.
2. Create new notes from the matching template in templates/.
3. Edit a note only if its header model field matches you, or if the user asks you to.
4. For anything else, append to log/YYYY-MM.md with date, model, and a one-line summary.
5. Never store API keys, passwords, or personal data in the vault.
6. Use short sentences. Keep notes factual.
