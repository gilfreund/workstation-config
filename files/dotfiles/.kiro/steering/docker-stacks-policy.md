# KIRO DOCKER STACKS TEMPLATE PROMPT

You are generating Docker stacks for a homelab repository. **ALL stacks MUST live in `docker/<stack-name>/`**. Follow these rules EXACTLY.

## REPOSITORY STRUCTURE

```text
.
├── docker/
│   ├── <stack-name>/
│   │   ├── .env.example
│   │   ├── .gitignore
│   │   ├── README.md
│   │   ├── Dockerfile
│   │   └── docker-compose.yml
│   └── ...
├── .gitignore
├── .env.example
├── README.md
└── docker-compose.yml
```

## ROOT .gitignore

```gitignore
# Environment files
.env
.env.local
.env.*.local

# Global temp/cache/logs
*.log
logs/
tmp/
cache/
temp/

# OS generated
.DS_Store
Thumbs.db

# IDE/editor
.vscode/
.idea/
*.swp
*.swo
```

## STACK .gitignore

Create `docker/<stack-name>/.gitignore` for each stack, and only include ignores relevant to that stack.

Example:
```gitignore
# Stack-specific database data
mysql/data/
postgresql/data/
pgdata/
mongodb/data/
redis/data/

# Stack-specific volumes/data
data/
volumes/
local-data/
storage/

# Stack-specific cache/temp/logs
cache/
tmp/
temp/
logs/
*.log

# Stack secrets
secrets/
.env
.env.local
.env.*
```

## ENVIRONMENT FILES

### Root .env.example

```bash
# Shared configuration
# Copy this file to .env and adjust for your environment
DOMAIN=example.com
TIMEZONE=UTC
COMPOSE_PROJECT_NAME=docker
```

### Stack .env.example

For every stack that uses a `.env`, create `docker/<stack-name>/.env.example`.

Example:
```bash
# Stack-specific configuration
# Copy this file to .env and replace with real values

# Database connection
DB_HOST=database
DB_PORT=3306
DB_NAME=myapp
DB_USER=appuser
DB_PASS=change_me

# Service credentials
API_KEY=example_api_key
SECRET_TOKEN=example_secret_token

# App settings
APP_SECRET=example_app_secret
DEBUG=false
```

Rules:
- Never commit real `.env` files
- Every ignored `.env` file must have a matching `.env.example`
- `.env.example` files must include comments and safe sample values

## SECRETS HANDLING

Before committing, check all configuration files for sensitive data.

Sensitive data includes:
- API keys
- Tokens
- Passwords
- Private URLs with credentials
- Certificates or private keys
- Any other secrets

If sensitive data is found:
- Remove it from the tracked config file
- Move it to `.env` or a secret file
- Ensure the secret file is ignored by git

## DOCKER RULES

- Each stack must be self-contained inside `docker/<stack-name>/`
- Each stack must include its own Docker setup such as `Dockerfile` and `docker-compose.yml`
- Use bind mounts or named volumes for persistent data
- Any persistent local data paths must be ignored in that stack's `.gitignore`
- Never hardcode credentials or secrets in Dockerfiles or compose files

## README REQUIREMENTS

### Root README.md

The root `README.md` must:
- Describe the repository purpose
- Explain that stacks are organized under `docker/<stack-name>/`
- Explain the general structure and usage pattern
- Not document each specific stack individually

Example structure:
```markdown
# Docker Homelab Repository

## Structure

All stacks are stored under `docker/<stack-name>/`.

Each stack is self-contained and includes its own:
- Docker configuration
- Environment example file
- README
- Stack-specific `.gitignore`

## Usage

General workflow:
1. Go to the desired stack directory
2. Copy `.env.example` to `.env`
3. Edit the environment values
4. Run `docker compose up -d`
```

### Stack README.md

Each stack must have its own `docker/<stack-name>/README.md`.

Each stack README must include:
- Purpose of the stack
- How to run it
- Required environment variables
- Volume/data directory behavior
- Any stack-specific notes

Example:
```markdown
# Example Stack

## Purpose

Short description of what this stack does.

## Quick Start

```bash
cp .env.example .env
# edit .env
docker compose up -d
```

## Environment Variables

See `.env.example` for required values.

## Data and Volumes

Runtime data is stored in local data directories or volumes that are excluded from git.
```

## VALIDATION CHECKLIST

Before finalizing any Docker stack, verify:

- [ ] Stack lives in `docker/<stack-name>/`
- [ ] `docker-compose.yml` is present
- [ ] `.env.example` exists with all required variables documented
- [ ] `.gitignore` covers all data directories and secret files
- [ ] No credentials or secrets are hardcoded
- [ ] `README.md` documents purpose, usage, and environment variables
- [ ] Persistent data paths are bind-mounted or use named volumes
- [ ] Stack is self-contained and does not depend on files outside its directory
