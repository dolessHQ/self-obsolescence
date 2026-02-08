#!/usr/bin/env bash
set -euo pipefail

# Cursor-style "fetch_rules" selector (shell implementation)
# Supports:
#   - .cursor/rules/**/*.mdc (frontmatter with description, globs, alwaysApply)
#   - .cursor/rules/**/*.md  (simple markdown, treated as always-apply)
#   - AGENTS.md files (root and nested subdirectories)
#   - Legacy .cursorrules at repo root
#
# Selects rules by alwaysApply, globs, description overlap, explicit reference
# Prints summary + full content

PROMPT=""
USE_GIT_DIFF=0
FILES=()
EXPLICIT=()

usage() {
  cat <<'EOF'
Usage:
  fetch_rules.sh --prompt "<task>" [--files f1 f2 ...] [--use-git-diff] [--explicit rule1.mdc rule2.md ...]

Options:
  --prompt        Task/request text (required)
  --files         File paths to consider for glob matching (optional)
  --use-git-diff  Add `git diff --name-only` files as hints (optional)
  --explicit      Force-include rules by filename (optional)

Supported rule formats:
  .cursor/rules/*.mdc   Rules with frontmatter (description, globs, alwaysApply)
  .cursor/rules/*.md    Simple markdown rules (treated as always-apply)
  AGENTS.md             Agent instructions (root and subdirectories)
  .cursorrules          Legacy format (root only)

Output: Markdown to stdout.
EOF
}

# --- arg parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)
      shift
      PROMPT="${1:-}"
      ;;
    --files)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        FILES+=("$1")
        shift
      done
      continue
      ;;
    --use-git-diff)
      USE_GIT_DIFF=1
      ;;
    --explicit)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        EXPLICIT+=("$1")
        shift
      done
      continue
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage; exit 2
      ;;
  esac
  shift
done

if [[ -z "${PROMPT}" ]]; then
  echo "--prompt is required" >&2
  usage
  exit 2
fi

# --- helpers ---
lower() { tr '[:upper:]' '[:lower:]'; }

repo_root() {
  if command -v git >/dev/null 2>&1; then
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
      git rev-parse --show-toplevel
      return
    fi
  fi
  pwd
}

# Return parent chain from root->cwd inclusive
parent_chain() {
  local root="$1"
  local cwd="$2"

  # build reversed chain cwd->root
  local cur="$cwd"
  local tmp=()
  while :; do
    tmp+=("$cur")
    [[ "$cur" == "$root" ]] && break
    local parent
    parent="$(cd "$cur/.." && pwd)"
    [[ "$parent" == "$cur" ]] && break
    cur="$parent"
  done

  # reverse
  for ((i=${#tmp[@]}-1; i>=0; i--)); do
    echo "${tmp[$i]}"
  done
}

# Very light path extraction from prompt (avoid URLs)
guess_files_from_prompt() {
  # matches foo/bar.ext, ./x.sql etc; excludes https://
  echo "$PROMPT" | \
    perl -ne 'while(/(?<!https?:\/\/)(?:\.\/)?[A-Za-z0-9_\-\/\.]+\.[A-Za-z0-9]{1,8}/g){print "$&\n"}' 2>/dev/null || true
}

git_diff_files() {
  if [[ "$USE_GIT_DIFF" -eq 1 ]] && command -v git >/dev/null 2>&1; then
    git diff --name-only 2>/dev/null || true
  fi
}

# Tokenize: lowercase, strip non-word, remove stopwords and short tokens
tokenize() {
  local s="$1"
  echo "$s" | lower | \
    tr -cs 'a-z0-9_-' ' ' | \
    awk '
      BEGIN{
        split("the a an and or to of in on for with without from by as at is are be been being it this that these those we you i they them their our your please help need want make do does did done can could should would will may", sw, " ");
        for(i in sw){stop[sw[i]]=1}
      }
      {
        for(i=1;i<=NF;i++){
          w=$i
          if(length(w)>2 && !(w in stop)) {print w}
        }
      }'
}

# Jaccard similarity of two token streams (best-effort)
jaccard() {
  local a="$1"
  local b="$2"
  awk -v A="$a" -v B="$b" '
    BEGIN{
      n=split(A, aa, " ");
      for(i=1;i<=n;i++){ if(aa[i]!=""){setA[aa[i]]=1} }
      m=split(B, bb, " ");
      for(i=1;i<=m;i++){ if(bb[i]!=""){setB[bb[i]]=1} }
      inter=0; uni=0;
      for(k in setA){ uni++; if(k in setB) inter++; }
      for(k in setB){ if(!(k in setA)) uni++; }
      if(uni==0){print 0; exit}
      print inter/uni;
    }'
}

# Check if file has YAML frontmatter (starts with ---)
has_frontmatter() {
  local file="$1"
  head -n 1 "$file" 2>/dev/null | grep -q '^---[[:space:]]*$'
}

# Parse frontmatter from .mdc or .md files with frontmatter
# outputs: alwaysApply|globs|description
parse_frontmatter() {
  local file="$1"
  # extract between first two --- lines
  awk '
    BEGIN{in_fm=0}
    /^---[[:space:]]*$/ { if(in_fm==0){in_fm=1; next} else {exit} }
    { if(in_fm==1) print }
  ' "$file" | \
  awk -F: '
    function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
    BEGIN{always=""; globs=""; desc=""}
    {
      key=trim($1)
      val=trim(substr($0, index($0,$2)))
      if(key=="alwaysApply" || key=="always_apply"){always=val}
      else if(key=="globs"){globs=val}
      else if(key=="description"){desc=val}
    }
    END{ print always "|" globs "|" desc }
  '
}

# Get metadata for a rule file
# For .mdc files: parse frontmatter
# For .md files without frontmatter: treat as always-apply
# outputs: alwaysApply|globs|description|format
get_rule_metadata() {
  local file="$1"
  local ext="${file##*.}"
  
  if [[ "$ext" == "mdc" ]] || has_frontmatter "$file"; then
    local meta
    meta="$(parse_frontmatter "$file")"
    echo "${meta}|mdc"
  else
    # Simple .md file without frontmatter - treat as always-apply
    echo "true|||md"
  fi
}

# Collect rules from a .cursor/rules dir (both .md and .mdc files)
collect_rules() {
  local rules_dir="$1"
  local scope_root="$2" # directory containing .cursor
  [[ -d "$rules_dir" ]] || return 0
  # find .md and .mdc files
  while IFS= read -r -d '' f; do
    echo "$f|$scope_root"
  done < <(find "$rules_dir" -type f \( -name "*.mdc" -o -name "*.md" \) -print0 2>/dev/null)
}

# Collect AGENTS.md files from root to cwd
collect_agents_md() {
  local root="$1"
  local cwd="$2"
  
  while IFS= read -r dir; do
    if [[ -f "$dir/AGENTS.md" ]]; then
      echo "$dir/AGENTS.md|$dir"
    fi
  done < <(parent_chain "$root" "$cwd")
}

# Bash pattern match for globs: any file matches any pattern
glob_match_any() {
  local patterns_csv="$1"
  shift
  local files=("$@")
  IFS=',' read -r -a pats <<< "$patterns_csv"
  for pat in "${pats[@]}"; do
    pat="$(echo "$pat" | awk '{$1=$1;print}')" # trim
    [[ -z "$pat" ]] && continue
    for f in "${files[@]}"; do
      [[ -z "$f" ]] && continue
      if [[ "$f" == $pat ]]; then
        return 0
      fi
    done
  done
  return 1
}

# --- main ---
ROOT="$(repo_root)"
CWD="$(pwd)"

# Candidate files for matching
mapfile -t PROMPT_FILES < <(guess_files_from_prompt | awk 'NF' | sort -u)
mapfile -t DIFF_FILES < <(git_diff_files | awk 'NF' | sort -u)

ALL_FILES=("${FILES[@]}" "${PROMPT_FILES[@]}" "${DIFF_FILES[@]}")
# de-dupe stable
DEDUP_FILES=()
declare -A seen_file=()
for f in "${ALL_FILES[@]}"; do
  [[ -z "$f" ]] && continue
  if [[ -z "${seen_file[$f]+x}" ]]; then
    seen_file[$f]=1
    DEDUP_FILES+=("$f")
  fi
done

# Explicit references via @rule.mdc or @rule.md in prompt
while IFS= read -r m; do
  EXPLICIT+=("$m")
done < <(echo "$PROMPT" | perl -ne 'while(/@([A-Za-z0-9_\-\.]+\.(?:mdc|md))/g){print "$1\n"}' 2>/dev/null || true)

# Collect all rule candidates from scoped dirs (.md and .mdc)
RULE_ROWS=()
while IFS= read -r dir; do
  rules_dir="$dir/.cursor/rules"
  scope_root="$dir/.cursor"
  while IFS= read -r row; do
    [[ -n "$row" ]] && RULE_ROWS+=("$row") # file|scope_root
  done < <(collect_rules "$rules_dir" "$scope_root")
done < <(parent_chain "$ROOT" "$CWD")

# Collect AGENTS.md files
AGENTS_MD_ROWS=()
while IFS= read -r row; do
  [[ -n "$row" ]] && AGENTS_MD_ROWS+=("$row") # file|scope_dir
done < <(collect_agents_md "$ROOT" "$CWD")

# Legacy .cursorrules
LEGACY=""
if [[ -f "$ROOT/.cursorrules" ]]; then
  LEGACY="$ROOT/.cursorrules"
fi

# Precompute prompt tokens
PROMPT_TOKS="$(tokenize "$PROMPT" | tr '\n' ' ' | awk '{$1=$1;print}')"

# Selection state: best rule per filename is the one with deepest scope (closest to cwd)
declare -A best_path=()    # name -> file path
declare -A best_scope=()   # name -> scope root
declare -A best_depth=()   # name -> depth (int)
declare -A best_why=()     # name -> why string
declare -A best_format=()  # name -> format (mdc, md)

depth_of() { # count path segments
  local p="$1"
  awk -v P="$p" 'BEGIN{n=split(P,a,"/"); print n}'
}

select_candidate() {
  local name="$1" file="$2" scope="$3" why="$4" format="${5:-mdc}"
  local d
  d="$(depth_of "$scope")"
  if [[ -z "${best_path[$name]+x}" || "$d" -gt "${best_depth[$name]}" ]]; then
    best_path[$name]="$file"
    best_scope[$name]="$scope"
    best_depth[$name]="$d"
    best_why[$name]="$why"
    best_format[$name]="$format"
  fi
}

# Pass 1: alwaysApply (including simple .md files)
for row in "${RULE_ROWS[@]}"; do
  file="${row%%|*}"
  scope="${row#*|}"
  name="$(basename "$file")"
  meta="$(get_rule_metadata "$file")"
  always="${meta%%|*}"
  rest="${meta#*|}"
  globs="${rest%%|*}"
  rest2="${rest#*|}"
  desc="${rest2%%|*}"
  format="${rest2#*|}"
  if [[ "$(echo "$always" | lower)" =~ ^(true|yes|1|on)$ ]]; then
    if [[ "$format" == "md" ]]; then
      select_candidate "$name" "$file" "$scope" "always-apply (.md)" "$format"
    else
      select_candidate "$name" "$file" "$scope" "alwaysApply:true" "$format"
    fi
  fi
done

# Pass 2: glob match
for row in "${RULE_ROWS[@]}"; do
  file="${row%%|*}"
  scope="${row#*|}"
  name="$(basename "$file")"
  [[ -n "${best_path[$name]+x}" ]] && continue
  meta="$(get_rule_metadata "$file")"
  always="${meta%%|*}"
  rest="${meta#*|}"
  globs="${rest%%|*}"
  rest2="${rest#*|}"
  desc="${rest2%%|*}"
  format="${rest2#*|}"
  if [[ -n "$globs" ]]; then
    if glob_match_any "$globs" "${DEDUP_FILES[@]}"; then
      select_candidate "$name" "$file" "$scope" "glob match: $globs" "$format"
    fi
  fi
done

# Pass 3: description match (no globs, not alwaysApply)
# Score all candidates, pick those above threshold, and best-effort top 1.
declare -A desc_score=()
declare -A desc_file=()
declare -A desc_scope=()
declare -A desc_format=()
for row in "${RULE_ROWS[@]}"; do
  file="${row%%|*}"
  scope="${row#*|}"
  name="$(basename "$file")"
  [[ -n "${best_path[$name]+x}" ]] && continue
  meta="$(get_rule_metadata "$file")"
  always="${meta%%|*}"
  rest="${meta#*|}"
  globs="${rest%%|*}"
  rest2="${rest#*|}"
  desc="${rest2%%|*}"
  format="${rest2#*|}"
  [[ -n "$globs" ]] && continue
  [[ "$(echo "$always" | lower)" =~ ^(true|yes|1|on)$ ]] && continue
  [[ -z "$desc" ]] && continue

  DESC_TOKS="$(tokenize "$desc" | tr '\n' ' ' | awk '{$1=$1;print}')"
  s="$(jaccard "$PROMPT_TOKS" "$DESC_TOKS")"
  desc_score["$name"]="$s"
  desc_file["$name"]="$file"
  desc_scope["$name"]="$scope"
  desc_format["$name"]="$format"
done

# Select those >= 0.06
for name in "${!desc_score[@]}"; do
  s="${desc_score[$name]}"
  awk -v S="$s" 'BEGIN{exit !(S>=0.06)}' && \
    select_candidate "$name" "${desc_file[$name]}" "${desc_scope[$name]}" "description match ($(printf "%.2f" "$s"))" "${desc_format[$name]}"
done

# Best-effort top1 if none selected by description
any_desc=0
for name in "${!best_why[@]}"; do
  [[ "${best_why[$name]}" == description* ]] && any_desc=1
done

if [[ "$any_desc" -eq 0 && "${#desc_score[@]}" -gt 0 ]]; then
  # find max score
  bestn=""
  bests="0"
  for name in "${!desc_score[@]}"; do
    s="${desc_score[$name]}"
    awk -v A="$s" -v B="$bests" 'BEGIN{exit !(A>B)}' && { bests="$s"; bestn="$name"; }
  done
  awk -v S="$bests" 'BEGIN{exit !(S>=0.03)}' && \
    select_candidate "$bestn" "${desc_file[$bestn]}" "${desc_scope[$bestn]}" "description match ($(printf "%.2f" "$bests")) [best-effort]" "${desc_format[$bestn]}"
fi

# Pass 4: explicit-only rules referenced
# explicit-only: no desc, no globs, not alwaysApply
declare -A explicit_set=()
for e in "${EXPLICIT[@]}"; do
  explicit_set["$e"]=1
done

for row in "${RULE_ROWS[@]}"; do
  file="${row%%|*}"
  scope="${row#*|}"
  name="$(basename "$file")"
  [[ -n "${best_path[$name]+x}" ]] && continue
  [[ -z "${explicit_set[$name]+x}" ]] && continue
  meta="$(get_rule_metadata "$file")"
  always="${meta%%|*}"
  rest="${meta#*|}"
  globs="${rest%%|*}"
  rest2="${rest#*|}"
  desc="${rest2%%|*}"
  format="${rest2#*|}"
  [[ -n "$desc" ]] && continue
  [[ -n "$globs" ]] && continue
  [[ "$(echo "$always" | lower)" =~ ^(true|yes|1|on)$ ]] && continue
  select_candidate "$name" "$file" "$scope" "explicit reference" "$format"
done

# --- output ---
echo "# Cursor-style rules selected"
echo

has_any_rules=0
[[ "${#best_path[@]}" -gt 0 ]] && has_any_rules=1
[[ "${#AGENTS_MD_ROWS[@]}" -gt 0 ]] && has_any_rules=1
[[ -n "$LEGACY" ]] && has_any_rules=1

if [[ "$has_any_rules" -eq 0 ]]; then
  echo "No rules found."
  echo
  exit 0
fi

if [[ "${#best_path[@]}" -gt 0 ]]; then
  echo "## Project Rules"
  echo
  echo "| Rule | Scope | Why |"
  echo "|---|---|---|"

  # Sort by depth desc, then name
  while IFS=$'\t' read -r name depth; do
    scope="${best_scope[$name]}"
    why="${best_why[$name]}"
    # scope display: directory containing .cursor (strip '/.cursor')
    scope_disp="${scope%/.cursor}"
    scope_disp="${scope_disp#"$ROOT"/}"
    [[ -z "$scope_disp" || "$scope_disp" == "$scope" ]] && scope_disp="."
    echo "| \`$name\` | \`$scope_disp\` | $why |"
  done < <(
    for name in "${!best_path[@]}"; do
      echo -e "$name\t${best_depth[$name]}"
    done | sort -k2,2nr -k1,1
  )
  echo
  echo "### Rule contents"
  echo

  while IFS=$'\t' read -r name depth; do
    file="${best_path[$name]}"
    why="${best_why[$name]}"
    format="${best_format[$name]}"
    rel="${file#"$ROOT"/}"
    echo "#### $name"
    echo
    echo "- Path: \`$rel\`"
    echo "- Selected because: **$why**"
    echo
    if [[ "$format" == "md" ]]; then
      echo '```markdown'
    else
      echo '```mdc'
    fi
    cat "$file"
    echo
    echo '```'
    echo
  done < <(
    for name in "${!best_path[@]}"; do
      echo -e "$name\t${best_depth[$name]}"
    done | sort -k2,2nr -k1,1
  )
fi

if [[ "${#AGENTS_MD_ROWS[@]}" -gt 0 ]]; then
  echo "## AGENTS.md Files"
  echo
  echo "| File | Scope |"
  echo "|---|---|"
  
  for row in "${AGENTS_MD_ROWS[@]}"; do
    file="${row%%|*}"
    scope="${row#*|}"
    rel="${file#"$ROOT"/}"
    scope_disp="${scope#"$ROOT"/}"
    [[ -z "$scope_disp" || "$scope_disp" == "$scope" ]] && scope_disp="."
    echo "| \`$rel\` | \`$scope_disp\` |"
  done
  echo
  echo "### AGENTS.md contents"
  echo
  
  for row in "${AGENTS_MD_ROWS[@]}"; do
    file="${row%%|*}"
    scope="${row#*|}"
    rel="${file#"$ROOT"/}"
    scope_disp="${scope#"$ROOT"/}"
    [[ -z "$scope_disp" || "$scope_disp" == "$scope" ]] && scope_disp="."
    echo "#### $rel"
    echo
    echo "- Scope: \`$scope_disp\`"
    echo
    echo '```markdown'
    cat "$file"
    echo
    echo '```'
    echo
  done
fi

if [[ -n "$LEGACY" ]]; then
  echo "## Legacy .cursorrules"
  echo
  echo "- Path: \`.cursorrules\`"
  echo "- Note: This format is deprecated. Consider migrating to Project Rules or AGENTS.md."
  echo
  echo '```'
  cat "$LEGACY"
  echo
  echo '```'
  echo
fi
