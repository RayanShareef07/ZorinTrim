#!/usr/bin/env bash
set -euo pipefail

readonly VERSION="0.2.0"
readonly SUPPORTED_ZORIN_VERSION="18.1"

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

print_heading() {
  local title="$1"
  printf '\n%s\n' "$title"
  printf '%s\n' "${title//?/-}"
}

# Runs a compatibility predicate, prints its PASS/FAIL line, and tracks
# failures for the final support status.
run_check() {
  local label="$1"
  local predicate="$2"

  if "$predicate"; then
    printf '  [PASS] %s\n' "$label"
  else
    printf '  [FAIL] %s\n' "$label"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
  fi
}

print_system_info() {
  print_heading "System Information"
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
  print_heading "Privilege Status"
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
  print_heading "Compatibility Checks"
  run_check "Distribution is Zorin OS" is_zorin_os
  run_check "Zorin OS version is $SUPPORTED_ZORIN_VERSION" is_supported_zorin_version
  run_check "apt is available" has_apt
  run_check "dpkg is available" has_dpkg
}

print_final_status() {
  print_heading "Final Support Status"
  if [ "$CHECKS_FAILED" -eq 0 ]; then
    printf '  SUPPORTED - this system meets all requirements for ZorinTrim.\n'
  else
    printf '  UNSUPPORTED - ZorinTrim only supports Zorin OS %s.\n' "$SUPPORTED_ZORIN_VERSION"
    printf '  See the FAIL entries above for the specific reason(s).\n'
  fi
  printf '\nNo changes were made to this system.\n'
}

main() {
  printf 'ZorinTrim v%s - Detection Engine\n' "$VERSION"

  print_system_info
  print_privilege_status
  print_compatibility_results
  print_final_status

  if [ "$CHECKS_FAILED" -eq 0 ]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
