# Calorie AI

A small Rails app for logging meals and calories by day. You can add entries manually or use **AI-assisted analysis** from a meal photo (via [RubyLLM](https://github.com/crmne/ruby_llm) and a vision-capable model).

## Prerequisites

- Ruby (version in `.ruby-version`)
- PostgreSQL running locally
- An **Anthropic API key** if you want photo analysis (Claude vision)

## Configuration

Create a `.env` file in the project root (loaded in development/test via `dotenv-rails`):

```bash
ANTHROPIC_API_KEY=your_key_here
```

The default model is set in `config/initializers/ruby_llm.rb` (currently `claude-haiku-4-5`).

## Setup

```bash
bundle install
bin/rails db:prepare
```

Or use the full setup script (installs gems, prepares the DB, then starts the dev server unless you pass `--skip-server`):

```bash
bin/setup
```

## Running the app

```bash
bin/dev
```

Then open [http://localhost:3000](http://localhost:3000) (root redirects to today’s log).

## Tests and quality

```bash
bin/rails test              # unit / model / request tests
bin/rails test:system       # browser tests (needs Chrome / Selenium)
bin/rubocop                 # Ruby style (Standard)
bin/ci                      # local CI script (see `config/ci.rb`)
```

GitHub Actions runs linting, security scans, and tests; see `.github/workflows/ci.yml`.
