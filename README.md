# Tempo Client

A CLI for managing Tempo timesheets via the Tempo and Jira APIs.

## Installation

### Prerequisites

- Ruby 3.x
- Bundler

### Clone and install

```sh
git clone git@github.com:your-user/tempo-client.git
cd tempo-client
bundle install
```

### Add a shell alias

Add this to your `~/.zshrc` (or `~/.bashrc`):

```sh
alias tempo='/path/to/tempo-client/bin/tempo'
```

Then reload your shell:

```sh
source ~/.zshrc
```

### Configuration

Create a `.env` file in the project root with the following variables:

```
TEMPO_API_TOKEN=your_tempo_api_token
JIRA_API_TOKEN=your_jira_api_token
JIRA_EMAIL=your_jira_email
JIRA_BASE_URL=https://your-org.atlassian.net
```

- **TEMPO_API_TOKEN** — Generate from Tempo > Settings > API Integration
- **JIRA_API_TOKEN** — Generate from https://id.atlassian.com/manage-profile/security/api-tokens
- **JIRA_EMAIL** — The email address associated with your Jira account
- **JIRA_BASE_URL** — Your Jira instance URL (e.g. `https://your-org.atlassian.net`)

## Usage

```
bin/tempo COMMAND [OPTIONS]
```

Run `bin/tempo help` for a list of commands, or `bin/tempo help COMMAND` for details on a specific command.

### View timesheets

```sh
# Today
bin/tempo view

# Specific date
bin/tempo view 2026-03-19

# Date range
bin/tempo view --from 2026-03-17 --to 2026-03-21
```

Output includes worklog IDs (prefixed with `#`), issue keys, hours, and descriptions.

### Log time

```sh
# Log 3 hours to an issue today
bin/tempo log PROJ-32 3 --description "Standup and code review"

# Log to a specific date
bin/tempo log PROJ-32 1.5 --date 2026-03-18 --description "Planning"
```

### Edit a worklog

Use the worklog ID shown in `view` output.

```sh
# Change hours
bin/tempo edit 185996 --hours 2.5

# Change description
bin/tempo edit 185996 --description "Updated description"

# Change date
bin/tempo edit 185996 --date 2026-03-20

# Combine multiple changes
bin/tempo edit 185996 --hours 4 --description "Full day" --date 2026-03-21
```

### Delete a worklog

```sh
bin/tempo delete 185996
```

### Duplicate timesheets

```sh
# Copy all worklogs from one day to another
bin/tempo duplicate 2026-03-19 2026-03-20

# Copy an entire week (Monday-Friday) to the following week
bin/tempo duplicate-week 2026-03-17

# Copy a week to 2 weeks later
bin/tempo duplicate-week 2026-03-17 2
```

### Browse Jira projects and issues

```sh
# List all projects
bin/tempo projects

# List issues in a project
bin/tempo issues PROJ

# Filter by status
bin/tempo issues PROJ --status "In Progress"

# Limit results
bin/tempo issues PROJ --max 10
```

### Current user info

```sh
bin/tempo whoami
```
