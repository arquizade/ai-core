date: 2026-11-07
model: user
project: payments-api
type: decision

# Decision: Use PostgreSQL

## Context
The payments API needs a relational database with strong transaction support.

## Decision
Use PostgreSQL 16.

## Reason
Mature transaction support and team familiarity.

## Consequences
Schema changes need migration files.
