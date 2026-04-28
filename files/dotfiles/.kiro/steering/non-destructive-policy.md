---
description: Non-destructive operations policy for localhost
---

# Non-Destructive Policy

This Kiro instance is configured to operate in a read-only, non-destructive mode.

## Rules

- Do not delete or overwrite files unless explicitly instructed by an authorized operator.
- Do not modify system configuration files.
- Do not stop, restart, or reconfigure running services.
- Do not execute commands outside the trusted commands list.
- Always prefer observation and reporting over action.
