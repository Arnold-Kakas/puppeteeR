# Local development workflow (Positron)

Positron does not have a Build pane, but supports the same keyboard shortcuts as RStudio for package development.

## Keyboard shortcuts

| Action | Windows/Linux | Mac |
|---|---|---|
| `devtools::load_all()` | `Ctrl+Shift+L` | `Cmd+Shift+L` |
| `devtools::test()` | `Ctrl+Shift+T` | `Cmd+Shift+T` |
| `devtools::document()` | `Ctrl+Shift+D` | `Cmd+Shift+D` |
| `devtools::check()` | `Ctrl+Shift+E` | `Cmd+Shift+E` |

These work from anywhere — a source file, the console, wherever focus is.

## Console workflow

```r
# 1. Restore renv dependencies (once, or after renv.lock changes)
renv::restore()

# 2. Load the package into your session
devtools::load_all()

# 3. Run all tests
devtools::test()

# 4. Run a single test file (faster during dev)
testthat::test_file("tests/testthat/test-graph.R")

# 5. Regenerate docs after editing roxygen2 comments
devtools::document()

# 6. Full check (slow, run before committing)
devtools::check()
```

## Recommended dev loop

1. Edit a file in `R/`
2. `Ctrl+Shift+L` — reloads all source instantly
3. Call the function interactively in the console to poke at it
4. `Ctrl+Shift+T` — run tests
5. Repeat

No need to restart R between changes — `load_all()` handles it.

## Smoke test (no API key needed)

Paste into the console after `load_all()`:

```r
schema <- workflow_state(
  n   = list(default = 0L),
  out = list(default = list(), reducer = reducer_append())
)

runner <- state_graph(schema) |>
  add_node("double", function(s, cfg) list(n = s$get("n") * 2L, out = s$get("n"))) |>
  add_node("addten", function(s, cfg) list(n = s$get("n") + 10L, out = s$get("n"))) |>
  add_edge(START, "double") |>
  add_edge("double", "addten") |>
  add_edge("addten", END) |>
  compile()

final <- runner$invoke(list(n = 5L))
final$get("n")    # 20
final$get("out")  # list(5, 10)
```

## .Rprofile

Your `.Rprofile` only activates renv. Add this so `devtools` is auto-available in interactive sessions and the keyboard shortcuts work without explicitly loading it:

```r
source("renv/activate.R")

if (interactive()) {
  suppressMessages(require(devtools))
}
```

---

## GitHub Pages site (pkgdown)

Based on [R Packages 2nd ed., Chapter 22](https://r-pkgs.org/website.html).

### One-time setup

Run this once. It creates the GitHub Actions workflow, enables GitHub Pages on the `gh-pages`
branch, and adds the site URL to DESCRIPTION and `_pkgdown.yml`:

```r
usethis::use_pkgdown_github_pages()
```

This does four things automatically:
1. Creates `.github/workflows/pkgdown.yaml` — builds the site on every push to `main`
2. Calls `pkgdown::check_pkgdown()` to validate your `_pkgdown.yml`
3. Adds `^_pkgdown\\.yml$` and `^docs$` to `.Rbuildignore`
4. Enables GitHub Pages on your repo (requires the repo to already exist on GitHub)

If the repo is not yet on GitHub, push first then run the command.

### Build the site locally (preview)

```r
# Full build — writes to docs/
pkgdown::build_site()

# Rebuild one article only (faster)
pkgdown::build_article("use-cases")

# Rebuild reference docs only
pkgdown::build_reference()

# Check _pkgdown.yml for issues
pkgdown::check_pkgdown()
```

Open `docs/index.html` in a browser to preview.

### Automatic deployment (GitHub Actions)

After `use_pkgdown_github_pages()`, every push to `main` triggers the workflow:

```
push to main
  └── GitHub Actions runs pkgdown::build_site()
        └── pushes built site to gh-pages branch
              └── site live at https://arnold-kakas.github.io/puppeteeR/
```

You do not need to commit the `docs/` folder — Actions builds and deploys it. Keep `docs/` in
`.Rbuildignore` (already there) and optionally add it to `.gitignore`:

```
docs/
```

### Manual deploy (without GitHub Actions)

If you prefer to build and push the site manually:

```r
pkgdown::build_site()
```

Then commit and push the `docs/` folder:

```bash
git add docs/
git commit -m "Rebuild pkgdown site"
git push
```

Configure GitHub Pages to serve from `main` branch, `/docs` folder (not `gh-pages`).

---

## Versioning

Based on [R Packages 2nd ed., Chapter 21](https://r-pkgs.org/lifecycle.html#sec-lifecycle-version-number).

### Version number format

```
0.1.0          — released version (major.minor.patch)
0.1.0.9000     — development version (add .9000 after release)
```

The `.9000` suffix signals to users that this is an in-development build from GitHub, not a
stable release.

### Bump the version

Use `usethis::use_version()` — it edits DESCRIPTION, updates NEWS.md, and optionally commits:

```r
usethis::use_version("patch")   # 0.1.0 → 0.1.1  (bug fixes)
usethis::use_version("minor")   # 0.1.0 → 0.2.0  (new features, backwards compatible)
usethis::use_version("major")   # 0.1.0 → 1.0.0  (breaking changes)
usethis::use_version("dev")     # 0.1.0 → 0.1.0.9000  (back to dev after a release)
```

### NEWS.md

Keep a changelog. Set it up once:

```r
usethis::use_news_md()
```

Then before each release, document changes under the new version heading:

```markdown
# puppeteeR 0.2.0

## New features

* `debate_workflow()` now accepts a `judge` agent.
* `GraphRunner$stream()` yields `state_snapshot` at each step.

## Bug fixes

* `supervisor_workflow()` no longer errors when worker nodes are added
  after the conditional edge (#12).
```

pkgdown renders `NEWS.md` as the Changelog page automatically.

---

## Release workflow

End-to-end steps for shipping a new version, following R Packages 2nd ed.

### 1. Prepare the release

```r
# Make sure everything passes
devtools::check()

# Bump to release version (removes .9000 suffix)
usethis::use_version("minor")   # or "patch" / "major"

# Update NEWS.md — fill in the new version section
# Edit NEWS.md manually or via usethis::use_news_md()

# Regenerate docs
devtools::document()

# Final check
devtools::check()
```

### 2. Commit and tag

```bash
git add .
git commit -m "Release v0.2.0"

# Create an annotated tag
git tag -a v0.2.0 -m "Release v0.2.0"

# Push commits and the tag
git push
git push --tags
```

### 3. Create a GitHub Release

```bash
# Using GitHub CLI (gh)
gh release create v0.2.0 --title "v0.2.0" --notes-from-tag
```

Or go to GitHub → Releases → Draft a new release → choose the tag → paste NEWS.md content.

GitHub Actions will automatically rebuild the pkgdown site with the new version after the push.

### 4. Back to development

```r
# Bump to dev version immediately after release
usethis::use_version("dev")   # 0.2.0 → 0.2.0.9000

# Add a new section to NEWS.md
# # puppeteeR 0.2.0.9000

git add .
git commit -m "Begin development of 0.2.0.9000"
git push
```

### 5. Install specific versions from GitHub

```r
# Latest development version
pak::pak("Arnold-Kakas/puppeteeR")

# Specific release tag
pak::pak("Arnold-Kakas/puppeteeR@v0.2.0")

# Specific commit
pak::pak("Arnold-Kakas/puppeteeR@abc1234")
```

---

## Versioned pkgdown site

pkgdown can show a version dropdown with links to docs for past releases. Add to `_pkgdown.yml`:

```yaml
development:
  mode: auto
```

With `mode: auto`:
- Development versions (`.9000`) are labelled **"dev"** — served at `/dev/`
- Release versions get their own snapshot when you run `pkgdown::deploy_to_branch()`

To deploy a versioned snapshot on release:

```r
# On the release commit (before bumping to dev)
pkgdown::deploy_to_branch(branch = "gh-pages")
```

This preserves the release docs permanently even as the dev site evolves.
