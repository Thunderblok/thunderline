# Thunderline Linux Development Environment Migration Guide

> Transitioning from Windows/WSL to a native Linux workflow (September 2025 edition).
>
> This document is the authoritative, copy‑paste friendly runbook to get a new engineer (or a freshly rebuilt laptop) from bare metal to a fully productive Thunderline dev environment fast. **Bias: reproducibility, minimum friction, clear verification checkpoints.**

---
## 🔥 TL;DR Fast Path (Ubuntu 24.04 or Fedora 40+)
```bash
# 1. System packages (compiler toolchain, git, libssl, etc.)
# Ubuntu:
sudo apt update && sudo apt install -y build-essential git curl wget gnupg ca-certificates \
  libssl-dev libncurses5-dev libncursesw5-dev libreadline-dev libxml2-dev libxslt1-dev \
  libffi-dev zlib1g-dev automake autoconf m4 unzip pkg-config inotify-tools jq ripgrep

# Fedora:
sudo dnf groupinstall -y "Development Tools" && sudo dnf install -y git curl wget unzip m4 \
  openssl-devel ncurses-devel libffi-devel zlib-devel autoconf automake readline-devel \
  libxml2-devel libxslt-devel inotify-tools jq ripgrep

# 2. Install asdf (version manager for Erlang/Elixir/Node/Postgres client)
git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.1
printf '\n. "$HOME/.asdf/asdf.sh"\n. "$HOME/.asdf/completions/asdf.bash"\n' >> ~/.bashrc
source ~/.bashrc

# 3. Add plugins
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git
asdf plugin add direnv https://github.com/asdf-community/asdf-direnv.git

# 4. (Optional) import NodeJS release team keys (first time only)
bash ~/.asdf/plugins/nodejs/bin/import-release-team-keyring

# 5. Install required runtime versions (choose OTP 27 + Elixir 1.18.x to match mix.exs constraint)
ERLANG_VER=27.0 ELIXIR_VER=1.18.2 NODE_VER=20.17.0
asdf install erlang $ERLANG_VER
asdf install elixir $ELIXIR_VER
asdf install nodejs $NODE_VER
asdf global erlang $ERLANG_VER
asdf global elixir $ELIXIR_VER
asdf global nodejs $NODE_VER

# 6. Confirm
elixir -v
node -v

# 7. Hex/rebar bootstrap (safe re-run)
mix local.hex --force && mix local.rebar --force

# 8. PostgreSQL (pick ONE approach)
# A) Local package (Ubuntu)
sudo apt install -y postgresql postgresql-contrib
# B) Local package (Fedora)
sudo dnf install -y postgresql-server postgresql-contrib
# C) Docker (uniform team default) – RECOMMENDED
sudo usermod -aG docker $USER  # log out/in if newly added
mkdir -p ~/.docker
# Start only DB
docker compose up -d postgres

# 9. Clone & bootstrap
git clone https://github.com/Thunderblok/Thunderline.git
cd Thunderline
mix deps.get
mix setup   # runs ash.setup, assets setup/build, migrations (heuristic aware)

# 10. Start app
mix phx.server

# 11. Visit
xdg-open http://localhost:4000 2>/dev/null || echo "Open http://localhost:4000"
```
Skip deeper sections only if everything above worked.

---
## 1. Rationale For Moving Off Windows/WSL
| Reason | Benefit on Native Linux |
|--------|-------------------------|
| File I/O latency | ~2–6x faster incremental compiles (Beam + asset build) |
| inotify limit control | Stable Phoenix code reloader & Nx watchers |
| Docker socket | Fewer edge cases vs. WSL proxy layers |
| GPU / ML stack | Cleaner EXLA/Tensor runtimes (no translation overhead) |
| Ergonomics | Unified shell / fs semantics, easier scripting |

---
## 2. Base OS Preparation
Choose a mainstream LTS / current: **Ubuntu 24.04** or **Fedora 40+**. Avoid mixing distro package Erlang + asdf Elixir (version skew). Prefer **asdf for all language runtimes**.

### 2.1 System Package Checklist
See TL;DR block for per‑distro commands. Ensure these capabilities:
- build-essential / Development Tools
- OpenSSL headers
- ncurses, zlib, libffi (Erlang build dependencies)
- inotify-tools (dev health debugging)
- ripgrep (fast code search)
- jq (JSON processing for scripts)

### 2.2 Increase inotify Watches (hot reload stability)
```bash
# Persistent increase
echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/99-inotify.conf
sudo sysctl --system
```
Verify with: `sysctl fs.inotify.max_user_watches` (expect 524288+).

---
## 3. Runtime Version Management (asdf)
Why asdf?
- Single tool orchestrates Erlang, Elixir, Node
- Per‑project pin via `.tool-versions`
- Easy upgrades w/ rollback

Add a project `.tool-versions` (commit to repo optionally):
```
erlang 27.0
elixir 1.18.2-otp-27
nodejs 20.17.0
```
Note: Use the `-otp-27` variant for Elixir if you compiled OTP 27.

### 3.1 Erlang Build Flags (Optional Performance)
To enable JIT + dirty schedulers (normally default):
```bash
export KERL_CONFIGURE_OPTIONS="--enable-hipe --enable-shared-zlib --with-ssl"
```
Set before `asdf install erlang ...` if needed.

---
## 4. Phoenix & Tooling
You do **NOT** need the global phx.new archive; this is an existing project. Ensure:
```bash
mix phx.new --version   # optional sanity (should print Phoenix installer version if installed)
```
Otherwise ignore. The project ships Phoenix in deps; `mix phx.server` is enough.

### 4.1 Assets Toolchain
Project uses:
- esbuild (dev only)
- tailwind (managed via mix tasks)
- NodeJS 20.x stable
No global npm install required; tasks vendor internally. If you see missing binaries:
```bash
mix esbuild.install --if-missing
mix tailwind.install --if-missing
```

---
## 5. Database (PostgreSQL 16)
### 5.1 Docker (Preferred)
```bash
docker compose up -d postgres
# Health check
until docker exec thunderline_postgres pg_isready -U postgres >/dev/null 2>&1; do echo 'waiting for db'; sleep 1; done
```
### 5.2 Native Service
Ubuntu:
```bash
sudo -u postgres psql -c "CREATE DATABASE thunderline;"
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"
```
Fedora may require `sudo postgresql-setup --initdb` then `sudo systemctl enable --now postgresql`.

### 5.3 Environment Configuration
Default dev expects either `DATABASE_URL` or discrete PG vars. Example `.envrc` (with direnv):
```bash
export DATABASE_URL=ecto://postgres:postgres@localhost:5432/thunderline
export FEATURES_AI_CHAT_PANEL=1
export ENABLE_NDJSON=1
```
Then:
```bash
direnv allow   # if asdf-direnv integrated
```

---
## 6. Project Bootstrap & Verification
From repo root:
```bash
mix deps.get
mix setup          # idempotent; will skip deps.get if already satisfied
mix ecto.migrate   # safe if you want explicit DB sync
mix test           # optional; run base suite
```
### 6.1 Dev Health Script
```bash
bash scripts/dev_health.sh
```
Confirms: Docker, Postgres connectivity, version parity, inotify limits.

### 6.2 Interactive Console
```bash
iex -S mix phx.server
```
Try an Ash read to confirm resource + DB paths:
```elixir
# Inside iex
Ash.read!(Thunderline.Chat.Conversation |> Ash.Query.limit(1))
```

---
## 7. Ash & Igniter Workflow
Igniter already present (`{:igniter, "~> 0.6"}`). Typical ops:
```bash
mix igniter.list         # discover available generators (if custom ones added later)
mix igniter.ls           # alias
mix ash_postgres.generate_migrations
mix ecto.migrate
```
If adding a new Ash resource:
1. Create resource module under `lib/thunderline/<domain>/resources/...` using project patterns.
2. Run `mix ash_postgres.generate_migrations` (dry-run prints diff if no changes).
3. Commit new migration + resource.

### 7.1 Ash Jido (Optional)
Requirement: Elixir >= 1.18 (already satisfied). Enable via env:
```bash
export INCLUDE_ASH_JIDO=1
mix deps.get
```
The conditional block in `mix.exs` injects `{:ash_jido, ...}`.

---
## 8. Common Pitfalls & Fixes
| Symptom | Cause | Resolution |
|---------|-------|-----------|
| `relation "conversations" does not exist` | Missed migration | `mix ecto.migrate` |
| Phoenix code reload stops | Low inotify watches | Increase & relaunch shell |
| Credo custom check warnings | Incomplete Credo check implementation | Either finish or disable locally (do **not** commit disable without review) |
| `duplicate_table dag_snapshots` | Autogenerated overlapping migration | Trim migration (done in AddAiChat fix) |
| Slow `mix deps.get` | Source Git deps (Jido) | Cache `~/.mix` & `~/.hex` in CI; no action locally |

---
## 9. Performance Tweaks (Optional)
- Enable Beam dirty CPU schedulers (default ON modern OTP)
- Set `ERL_AFLAGS="+fnu"` to reduce unicode formatting overhead in heavy log environments
- Use `MIX_ENV=prod mix compile` for profiling (prod compile includes protocol consolidation)
- For Nx/EXLA GPU builds: install CUDA toolkit + set `EXLA_TARGET=cuda` (beyond scope here)

---
## 10. Security & Secrets Hygiene
Never commit real secrets. For local dev defaults:
```bash
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export TOKEN_SIGNING_SECRET=$(openssl rand -hex 32)
```
Add to `.envrc` (excluded via `.gitignore` if present).

---
## 11. Git & Tooling Conveniences
```bash
# Global git config enhancements
git config --global pull.rebase false
git config --global fetch.prune true

# Useful aliases
alias mt='mix test'
alias ms='mix setup'
alias msrv='iex -S mix phx.server'
```
Optionally add to `~/.bashrc`.

---
## 12. Upgrade Process (Coordinated)
1. Choose target versions (e.g., Erlang 27.1, Elixir 1.18.3).
2. Update `.tool-versions` → install via asdf.
3. Run `mix deps.update --all` (only if required libs need recompilation).
4. Run test + dialyzer + credo.
5. Regenerate migrations (`mix ash_postgres.generate_migrations --check --dry-run`) to ensure no drift introduced.
6. PR with changelog note.

---
## 13. Validation Checklist (Copy/Paste for Onboarding Ticket)
- [ ] asdf installed & global versions set (OTP 27 / Elixir 1.18.x / Node 20.x)
- [ ] `elixir -v` matches team baseline
- [ ] Postgres reachable (`pg_isready` OK)
- [ ] `mix setup` succeeded
- [ ] Phoenix boots (`mix phx.server`) and homepage loads
- [ ] Ash query works in iex
- [ ] Assets build without errors (tailwind, esbuild)
- [ ] inotify watch count ≥ 524288
- [ ] dev_health script all green

---
## 14. FAQ
**Q: Do I need Erlang solutions packages?**  
A: No. Prefer asdf builds for deterministic OTP + patch level control.

**Q: Dialyzer PLT build is slow—what now?**  
A: First build caches in `priv/plts`; reuse across machines by syncing that directory (optional). Do *not* commit PLTs to git.

**Q: Why not use Nix?**  
A: Could; team opted for asdf for lower cognitive surface (add later if desired).

**Q: GPU / ML acceleration?**  
A: Install CUDA + cuDNN then set `EXLA_TARGET=cuda`. Validate via `:nx.default_backend()` after loading EXLA.

---
## 15. Support Escalation Path
1. Run `bash scripts/dev_health.sh`
2. Share output + `elixir -v` + `mix hex.outdated` snippet
3. Check migrations status: `mix ecto.migrations | tail -n 15`
4. Fallback: remove `_build`, recompile: `rm -rf _build && mix compile`

If still blocked, open an engineering ops ticket labeled `onboarding`.

---
**You are now operational.**  
> “Aut viam inveniam aut faciam.” – Make telemetry your ally, and let the supervision tree crash early, heal fast.

⚡
