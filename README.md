# ai-core

Shared memory vault for every AI model you use. Claude Code, Codex, and Gemini CLI read the same rules and write to the same notes.

## Folder structure

```
ai-core/
├── CLAUDE.md          Rules for Claude Code
├── AGENTS.md          Rules for Codex and other agents
├── GEMINI.md          Rules for Gemini CLI
├── inbox/             Raw captures. Sort them each week.
├── planning/
│   ├── roadmap.md     Goals and milestones
│   ├── weekly/        One file per week
│   └── specs/         Feature specs written before you build
├── coding/
│   ├── architecture/  Stack choices and diagrams
│   ├── bugs/          Symptom, root cause, fix
│   ├── snippets/      Reusable code
│   └── setup/         Environment and deploy steps
├── projects/          One index note per project
├── decisions/         One dated note per decision
├── log/               Monthly append-only log
├── people/            Collaborators and working preferences
├── templates/         Starter files for new notes
└── archive/           Finished projects and old plans
```

## Setup

Use one of the options below.

### Option 1: Clone

```
git clone git@github.com:arquizade/ai-core.git ~/ai-core
cd ~/ai-core
```

### Option 2: Fork

Click Fork on GitHub, then clone your fork:

```
git clone git@github.com:arquizade/ai-core.git ~/ai-core
```

### Option 3: Create the folders with one command

This command creates the folder structure and starter files in ~/ai-core. Read the script before you run it.

```
curl -fsSL https://raw.githubusercontent.com/arquizade/ai-core/main/scripts/setup.sh | bash
```

To check whether a folder is already set up, without changing anything:

```
bash scripts/setup.sh --check --vault-dir ~/ai-core
```

## Next steps

1. Open ~/ai-core as a vault in Obsidian.
2. Connect each AI tool to the folder. Point Claude Code to CLAUDE.md, Codex to AGENTS.md, and Gemini CLI to GEMINI.md.
3. Replace the sample project and decision with your own work.
4. Commit after each session.

## Backup

Keep this repository private if it holds work notes. Never store API keys, passwords, or personal data in the vault. The .gitignore file blocks common secret files.

## Rules

All three rule files hold the same content. Edit them together.
