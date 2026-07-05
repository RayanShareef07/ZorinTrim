#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="0.5.0"
readonly SUPPORTED_ZORIN_VERSION="18.1"
readonly RULE_WIDTH=60

# Field separator for parsing raw dpkg-query output. A tab looks like the
# obvious choice, but bash's `read` treats tab as IFS whitespace and
# collapses consecutive delimiters - silently dropping empty fields (e.g.
# a package with no Essential value) and shifting later fields into the
# wrong variable. The ASCII Unit Separator can't appear in dpkg metadata
# and isn't treated as whitespace, so empty fields are preserved correctly.
readonly DPKG_FIELD_SEP=$'\x1f'

# Separator joining multiple evidence bullets inside a single tab-delimited
# analysis field. Same rationale as DPKG_FIELD_SEP: won't collide with real
# text and isn't treated as IFS whitespace, so bullets round-trip exactly.
readonly EVIDENCE_SEP=$'\x1e'

# --- Low-level detection -----------------------------------------------
#
# Every function in this section only reads system state; none of them
# write, install, remove, or configure anything.

detect_kernel_name() {
  uname -s
}

detect_kernel_version() {
  uname -r
}

detect_cpu_arch() {
  uname -m
}

# Extracts a single field from an os-release-style file without leaking
# its variables into the caller's shell. Prints "" if the file or field
# is missing.
detect_os_release_field() {
  local field="$1"
  local file="${2:-/etc/os-release}"
  if [ -r "$file" ]; then
    (
      # shellcheck disable=SC1090
      . "$file"
      printf '%s' "${!field:-}"
    ) || true
  else
    printf ''
  fi
}

detect_distro_name() {
  local name
  name="$(detect_os_release_field PRETTY_NAME)"
  printf '%s' "${name:-Unknown}"
}

detect_distro_id() {
  detect_os_release_field ID
}

detect_zorin_version() {
  local version
  version="$(detect_os_release_field VERSION_ID)"
  printf '%s' "${version:-Unknown}"
}

# Zorin OS ships upstream release metadata for the Ubuntu base it's built
# on. Not guaranteed to exist, so a missing file is not an error.
detect_ubuntu_base() {
  local base
  base="$(detect_os_release_field PRETTY_NAME /etc/upstream-release/os-release)"
  printf '%s' "${base:-Unavailable}"
}

detect_ram_total() {
  local value
  value="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')" || true
  printf '%s' "${value:-Unknown}"
}

detect_ram_available() {
  local value
  value="$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')" || true
  printf '%s' "${value:-Unknown}"
}

detect_disk_available() {
  local value
  value="$(df -h / 2>/dev/null | awk 'NR==2 {print $4}')" || true
  printf '%s' "${value:-Unknown}"
}

# Tries ping, then curl, then wget, in order, against public DNS servers.
# Reports "Unknown" rather than failing if no suitable tool exists.
detect_internet_status() {
  if command -v ping >/dev/null 2>&1; then
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
      printf 'Connected'
    else
      printf 'Not detected'
    fi
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -sI --max-time 3 https://1.1.1.1 >/dev/null 2>&1; then
      printf 'Connected'
    else
      printf 'Not detected'
    fi
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget -q --spider --timeout=3 https://1.1.1.1 >/dev/null 2>&1; then
      printf 'Connected'
    else
      printf 'Not detected'
    fi
    return
  fi

  printf 'Unknown'
}

is_root() {
  [ "$(id -u)" -eq 0 ]
}

has_sudo() {
  command -v sudo >/dev/null 2>&1
}

has_dpkg_query() {
  command -v dpkg-query >/dev/null 2>&1
}

# Classifies a single installed package into one of ZorinTrim's categories,
# based on the Debian Priority and Section fields dpkg already tracks.
# Priority wins when it signals the package is part of the base system.
# Anything not explicitly recognized below is left Uncategorized rather
# than guessed at.
classify_package() {
  local section="$1"
  local priority="$2"

  case "$priority" in
    required | important | standard)
      printf 'System / Essential'
      return
      ;;
  esac

  case "$section" in
    games) printf 'Games' ;;
    office) printf 'Office' ;;
    sound | video | graphics) printf 'Multimedia' ;;
    net | web | mail | news | comm) printf 'Internet' ;;
    utils | shells) printf 'Utilities' ;;
    devel | libdevel | python | perl | php | ruby | rust | java | javascript | haskell | interpreters | vcs)
      printf 'Development'
      ;;
    libs | kernel | x11 | metapackages | admin) printf 'System / Essential' ;;
    *) printf 'Uncategorized' ;;
  esac
}

# Prints "<category>\t<count>" for every category with at least one
# installed package, in a fixed display order, followed by a total line.
# Callers must check has_dpkg_query first.
detect_package_categories() {
  local -A counts=()
  local pkg section priority category total=0

  while IFS="$DPKG_FIELD_SEP" read -r pkg section priority; do
    [ -n "$pkg" ] || continue
    category="$(classify_package "$section" "$priority")"
    counts["$category"]=$(( ${counts["$category"]:-0} + 1 ))
    total=$((total + 1))
  done < <(dpkg-query -W -f="\${Package}${DPKG_FIELD_SEP}\${Section}${DPKG_FIELD_SEP}\${Priority}\n" 2>/dev/null)

  local order=("Games" "Office" "Multimedia" "Internet" "Utilities" "Development" "System / Essential" "Uncategorized")
  local name
  for name in "${order[@]}"; do
    if [ "${counts[$name]:-0}" -gt 0 ]; then
      printf '%s\t%s\n' "$name" "${counts[$name]}"
    fi
  done
  printf 'Total\t%s\n' "$total"
}

# Maps a risk level and category to exactly one recommendation. Analysis
# only - never used to decide whether anything is actually removed.
recommend_for() {
  local risk="$1"
  local category="$2"

  case "$risk" in
    CRITICAL) printf 'DO NOT REMOVE' ;;
    HIGH) printf 'KEEP (CORE)' ;;
    MEDIUM)
      if [ "$category" = "Uncategorized" ]; then
        printf 'KEEP'
      else
        printf 'REVIEW'
      fi
      ;;
    *) printf 'OPTIONAL' ;;
  esac
}

# Assesses a single package's removal risk and how confidently that risk
# can be trusted. dpkg's own Essential flag and required/important Priority
# are Debian's own authoritative "do not remove" facts, so they alone
# produce CRITICAL with HIGH confidence - they're direct records, not
# estimates. Below that, risk is the highest severity reached by combining
# several independent signals - standard Priority, being directly depended
# on by an installed metapackage, and package category - none of which
# decides the outcome on its own. Every signal that fired is recorded as a
# separate evidence entry.
#
# Confidence reflects how much of that evidence agrees:
#   - Uncategorized means the classification itself is unreliable, so
#     confidence is LOW regardless of what else fired (evidence is
#     insufficient by definition). recommend_for() already responds to this
#     by being more conservative (MEDIUM+Uncategorized -> KEEP instead of
#     REVIEW; HIGH-risk outcomes are already the most conservative
#     recommendation there is).
#   - Otherwise, confidence is HIGH when 2+ independent signals fired, and
#     MEDIUM when only one did. A fully permissive (LOW risk) package by
#     definition has no standard-priority or metapackage-dependency signal
#     firing, so its absence is itself real corroborating evidence - it's
#     stated explicitly rather than left as a silent gap.
analyze_package() {
  local package="$1"
  local section="$2"
  local priority="$3"
  local essential="$4"
  local is_dependent="$5"

  if [ "$essential" = "yes" ]; then
    printf '%s\tCRITICAL\tMarked essential by dpkg\tDO NOT REMOVE\tHIGH\n' "$package"
    return
  fi

  case "$priority" in
    required | important)
      printf '%s\tCRITICAL\tPriority "%s" - required for core system stability\tDO NOT REMOVE\tHIGH\n' "$package" "$priority"
      return
      ;;
  esac

  local category
  category="$(classify_package "$section" "$priority")"

  local -a evidence=()
  local severity=1 # 1=LOW 2=MEDIUM 3=HIGH

  if [ "$priority" = "standard" ]; then
    evidence+=("Priority \"standard\" - part of the base package set")
    [ "$severity" -ge 3 ] || severity=3
  fi

  if [ -n "$is_dependent" ]; then
    evidence+=("Depended on by an installed desktop metapackage")
    [ "$severity" -ge 3 ] || severity=3
  fi

  case "$category" in
    "System / Essential")
      evidence+=("Classified as System / Essential (section \"$section\")")
      [ "$severity" -ge 3 ] || severity=3
      ;;
    Development | Multimedia | Internet | Office)
      evidence+=("Classified as $category (optional software with meaningful functionality)")
      [ "$severity" -ge 2 ] || severity=2
      ;;
    Uncategorized)
      evidence+=("Could not be confidently classified")
      [ "$severity" -ge 2 ] || severity=2
      ;;
    *)
      evidence+=("Classified as $category (optional, independent of core desktop functionality)")
      ;;
  esac

  local risk
  case "$severity" in
    3) risk="HIGH" ;;
    2) risk="MEDIUM" ;;
    *) risk="LOW" ;;
  esac

  # Only reachable when neither standard priority nor a metapackage
  # dependency fired above - true by construction, not a guess.
  if [ "$risk" = "LOW" ]; then
    evidence+=("Priority \"$priority\" - not part of the base package set")
    evidence+=("Not required by any installed desktop metapackage")
  fi

  local confidence
  if [ "$category" = "Uncategorized" ]; then
    confidence="LOW"
  elif [ "${#evidence[@]}" -ge 2 ]; then
    confidence="HIGH"
  else
    confidence="MEDIUM"
  fi

  local reason=""
  local part
  for part in "${evidence[@]}"; do
    if [ -z "$reason" ]; then
      reason="$part"
    else
      reason="${reason}${EVIDENCE_SEP}${part}"
    fi
  done

  printf '%s\t%s\t%s\t%s\t%s\n' "$package" "$risk" "$reason" "$(recommend_for "$risk" "$category")" "$confidence"
}

# Prints "<package>\t<risk>\t<reason>\t<recommendation>\t<confidence>" for
# every installed package. Produces no output if dpkg-query is unavailable.
analyze_packages() {
  has_dpkg_query || return 0

  local data
  data="$(dpkg-query -W -f="\${Package}${DPKG_FIELD_SEP}\${Section}${DPKG_FIELD_SEP}\${Priority}${DPKG_FIELD_SEP}\${Essential}${DPKG_FIELD_SEP}\${Depends}\n" 2>/dev/null)" || true
  [ -n "$data" ] || return 0

  local -A metapackage_dependents=()
  local package section priority essential depends

  while IFS="$DPKG_FIELD_SEP" read -r package section priority essential depends; do
    [ "$section" = "metapackages" ] || continue
    local cleaned token
    cleaned="$(printf '%s' "$depends" | sed -E 's/\([^)]*\)//g; s/[,|]/ /g')"
    for token in $cleaned; do
      metapackage_dependents["${token%%:*}"]=1
    done
  done <<<"$data"

  while IFS="$DPKG_FIELD_SEP" read -r package section priority essential depends; do
    [ -n "$package" ] || continue
    analyze_package "$package" "$section" "$priority" "$essential" "${metapackage_dependents[$package]:-}"
  done <<<"$data"
}

# --- Compatibility predicates --------------------------------------------
#
# Each predicate reports pass/fail via exit status only, so it can be
# passed directly to run_check.

is_zorin_os() {
  [ "$(detect_distro_id)" = "zorin" ]
}

is_supported_zorin_version() {
  [ "$(detect_zorin_version)" = "$SUPPORTED_ZORIN_VERSION" ]
}

has_apt() {
  command -v apt >/dev/null 2>&1
}

has_dpkg() {
  command -v dpkg >/dev/null 2>&1
}

# --- Reporting ------------------------------------------------------------

CHECKS_FAILED=0
RULE_CHAR="-"
CHECK_MARK="[OK]"
CROSS_MARK="[FAIL]"
BULLET="*"
RULE_LINE=""

# A minimal locale check: only used to decide whether Unicode box-drawing
# and check/cross symbols are safe to print, or whether to fall back to
# plain ASCII. Never affects detection or compatibility results.
supports_utf8() {
  case "${LC_ALL:-}${LANG:-}" in
    *UTF-8* | *utf8* | *UTF8*) return 0 ;;
    *) return 1 ;;
  esac
}

make_rule() {
  local char="$1"
  local width="$2"
  local i
  local rule=""
  for ((i = 0; i < width; i++)); do
    rule+="$char"
  done
  printf '%s' "$rule"
}

# Sets the symbols used throughout the report. Must run once before any
# print_* function is called.
init_symbols() {
  if supports_utf8; then
    RULE_CHAR="━"
    CHECK_MARK="✔"
    CROSS_MARK="✘"
    BULLET="•"
  fi
  RULE_LINE="$(make_rule "$RULE_CHAR" "$RULE_WIDTH")"
}

print_rule() {
  printf '\n%s\n' "$RULE_LINE"
}

print_section() {
  local title="$1"
  print_rule
  printf '\n%s\n\n' "$title"
}

# Runs a compatibility predicate, prints its pass/fail line, and tracks
# failures for the final support status.
run_check() {
  local label="$1"
  local predicate="$2"

  if "$predicate"; then
    printf '  %s %s\n' "$CHECK_MARK" "$label"
  else
    printf '  %s %s\n' "$CROSS_MARK" "$label"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

print_system_info() {
  print_section "System Information"
  printf '  %-22s %s\n' "Operating System:" "$(detect_kernel_name)"
  printf '  %-22s %s\n' "Distribution:" "$(detect_distro_name)"
  printf '  %-22s %s\n' "Zorin OS Version:" "$(detect_zorin_version)"
  printf '  %-22s %s\n' "Ubuntu Base:" "$(detect_ubuntu_base)"
  printf '  %-22s %s\n' "Kernel Version:" "$(detect_kernel_version)"
  printf '  %-22s %s\n' "CPU Architecture:" "$(detect_cpu_arch)"
  printf '  %-22s %s\n' "Total RAM:" "$(detect_ram_total)"
  printf '  %-22s %s\n' "Available RAM:" "$(detect_ram_available)"
  printf '  %-22s %s\n' "Disk Space Available:" "$(detect_disk_available)"
  printf '  %-22s %s\n' "Internet Connectivity:" "$(detect_internet_status)"
}

print_privilege_status() {
  print_section "Privilege Status"
  if is_root; then
    printf '  %-22s %s\n' "Running as root:" "Yes"
  else
    printf '  %-22s %s\n' "Running as root:" "No"
  fi
  if has_sudo; then
    printf '  %-22s %s\n' "Sudo available:" "Yes"
  else
    printf '  %-22s %s\n' "Sudo available:" "No"
  fi
}

print_compatibility_results() {
  print_section "Compatibility"
  run_check "Zorin OS" is_zorin_os
  run_check "Version $SUPPORTED_ZORIN_VERSION" is_supported_zorin_version
  run_check "apt" has_apt
  run_check "dpkg" has_dpkg
}

# Skipped entirely if dpkg-query isn't available. Purely informational -
# classification never affects the support status.
print_package_categories() {
  has_dpkg_query || return 0

  print_section "Package Categories"
  local name count
  while IFS=$'\t' read -r name count; do
    printf '  %-20s %s\n' "$name:" "$count"
  done < <(detect_package_categories)
}

print_candidate_summary() {
  local analysis="$1"

  print_section "Candidate Analysis - Summary"

  local total=0
  local -A risk_counts=()
  local -A recommendation_counts=()
  local -A confidence_counts=()
  local package risk reason recommendation confidence

  while IFS=$'\t' read -r package risk reason recommendation confidence; do
    [ -n "$package" ] || continue
    total=$((total + 1))
    risk_counts["$risk"]=$(( ${risk_counts["$risk"]:-0} + 1 ))
    recommendation_counts["$recommendation"]=$(( ${recommendation_counts["$recommendation"]:-0} + 1 ))
    confidence_counts["$confidence"]=$(( ${confidence_counts["$confidence"]:-0} + 1 ))
  done <<<"$analysis"

  printf '  %-22s %s\n\n' "Packages analyzed:" "$total"

  printf '  By risk:\n'
  local risk_order=("CRITICAL" "HIGH" "MEDIUM" "LOW")
  for risk in "${risk_order[@]}"; do
    if [ "${risk_counts[$risk]:-0}" -gt 0 ]; then
      printf '    %-18s %s\n' "$risk" "${risk_counts[$risk]}"
    fi
  done

  printf '\n  By recommendation:\n'
  local recommendation_order=("DO NOT REMOVE" "KEEP (CORE)" "KEEP" "REVIEW" "OPTIONAL")
  for recommendation in "${recommendation_order[@]}"; do
    if [ "${recommendation_counts[$recommendation]:-0}" -gt 0 ]; then
      printf '    %-18s %s\n' "$recommendation" "${recommendation_counts[$recommendation]}"
    fi
  done

  printf '\n  By confidence:\n'
  local confidence_order=("HIGH" "MEDIUM" "LOW")
  for confidence in "${confidence_order[@]}"; do
    if [ "${confidence_counts[$confidence]:-0}" -gt 0 ]; then
      printf '    %-18s %s\n' "$confidence" "${confidence_counts[$confidence]}"
    fi
  done
}

# Prints one boxed Safety Validation card for a single actionable package:
# risk, recommendation, and confidence as labeled fields, followed by every
# piece of evidence as a bullet - so the recommendation always explains
# itself instead of asking the user to trust it.
print_candidate_card() {
  local package="$1" risk="$2" reason="$3" recommendation="$4" confidence="$5"

  print_rule
  printf '\n%s\n\n' "$package"
  printf 'Risk:\n%s\n\n' "$risk"
  printf 'Recommendation:\n%s\n\n' "$recommendation"
  printf 'Confidence:\n%s\n\n' "$confidence"
  printf 'Reason:\n\n'

  local -a items
  IFS="$EVIDENCE_SEP" read -r -a items <<<"$reason"
  local item
  for item in "${items[@]}"; do
    printf '  %s %s\n' "$BULLET" "$item"
  done
}

# Full detail cards for LOW and MEDIUM risk packages only - the ones a
# user could plausibly act on. HIGH/CRITICAL are covered by
# print_candidate_protected instead, as counts rather than individual
# cards, so the report doesn't turn into hundreds of "DO NOT REMOVE" lines.
print_candidate_actionable() {
  local analysis="$1"

  print_section "Candidate Analysis - Actionable Candidates"

  local package risk reason recommendation confidence
  local shown=0

  while IFS=$'\t' read -r package risk reason recommendation confidence; do
    [ -n "$package" ] || continue
    case "$risk" in
      LOW | MEDIUM)
        print_candidate_card "$package" "$risk" "$reason" "$recommendation" "$confidence"
        shown=$((shown + 1))
        ;;
    esac
  done <<<"$analysis"

  [ "$shown" -gt 0 ] || printf '  No actionable candidates found.\n'
}

# HIGH/CRITICAL packages are protected by design - shown as counts only,
# never as individual cards, since a typical system has hundreds of them.
print_candidate_protected() {
  local analysis="$1"

  print_section "Candidate Analysis - Protected Packages"

  local package risk reason recommendation confidence
  local critical=0
  local high=0

  while IFS=$'\t' read -r package risk reason recommendation confidence; do
    case "$risk" in
      CRITICAL) critical=$((critical + 1)) ;;
      HIGH) high=$((high + 1)) ;;
    esac
  done <<<"$analysis"

  printf '  %-10s %s packages (essential system / core desktop stability)\n' "CRITICAL" "$critical"
  printf '  %-10s %s packages (important desktop / core components)\n' "HIGH" "$high"
}

# Skipped entirely if dpkg-query isn't available, same as Package
# Categories. Analysis runs once and is shared across all three layers.
print_candidate_analysis() {
  has_dpkg_query || return 0

  local analysis
  analysis="$(analyze_packages)"
  [ -n "$analysis" ] || return 0

  print_candidate_summary "$analysis"
  print_candidate_actionable "$analysis"
  print_candidate_protected "$analysis"
}

print_final_status() {
  print_section "Result"
  if [ "$CHECKS_FAILED" -eq 0 ]; then
    printf '  SUPPORTED\n'
  else
    printf '  UNSUPPORTED\n'
  fi
  printf '\nNo changes were made to this system.\n'
}

main() {
  init_symbols

  printf 'ZorinTrim v%s - Detection Engine\n' "$VERSION"

  print_system_info
  print_privilege_status
  print_compatibility_results
  print_package_categories
  print_candidate_analysis
  print_final_status
  print_rule

  if [ "$CHECKS_FAILED" -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
