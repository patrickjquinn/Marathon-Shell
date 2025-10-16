#!/bin/bash
# Pre-Build Verification Script
# Checks that Marathon-Image repository is ready for building on Fedora

set -e

COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
    ((PASS++))
}

check_fail() {
    echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
    ((WARN++))
}

info() {
    echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $1"
}

echo "=== Marathon OS Pre-Build Verification ==="
echo ""

# Check if in correct directory
if [ ! -f "scripts/build-and-flash.sh" ]; then
    echo -e "${COLOR_RED}ERROR:${COLOR_RESET} Not in Marathon-Image root directory"
    echo "Please run this script from the repository root."
    exit 1
fi

info "Checking repository structure..."
echo ""

# 1. Check directory structure
echo "1. Directory Structure"
if [ -d "packages" ] && [ -d "configs" ] && [ -d "devices" ] && [ -d "docs" ] && [ -d "scripts" ]; then
    check_pass "Core directories exist"
else
    check_fail "Missing core directories"
fi

if [ -d "packages/marathon-base-config" ]; then
    check_pass "marathon-base-config package found"
else
    check_fail "marathon-base-config package missing"
fi

if [ -d "packages/marathon-shell" ]; then
    check_pass "marathon-shell package found"
else
    check_fail "marathon-shell package missing"
fi

if [ -d "packages/linux-marathon" ]; then
    check_pass "linux-marathon package found"
else
    check_fail "linux-marathon package missing"
fi

echo ""

# 2. Check essential files
echo "2. Essential Files"

ESSENTIAL_FILES=(
    "README.md"
    "LICENSE"
    "CONTRIBUTING.md"
    ".gitignore"
    "packages/marathon-base-config/APKBUILD"
    "packages/marathon-shell/APKBUILD"
    "packages/linux-marathon/APKBUILD"
    "scripts/build-and-flash.sh"
    "scripts/validate-system.sh"
)

for file in "${ESSENTIAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        check_pass "$file exists"
    else
        check_fail "$file missing"
    fi
done

# Check executability
if [ -x "scripts/build-and-flash.sh" ]; then
    check_pass "build-and-flash.sh is executable"
else
    check_warn "build-and-flash.sh not executable (will fix)"
    chmod +x scripts/build-and-flash.sh
fi

if [ -x "scripts/validate-system.sh" ]; then
    check_pass "validate-system.sh is executable"
else
    check_warn "validate-system.sh not executable (will fix)"
    chmod +x scripts/validate-system.sh
fi

echo ""

# 3. Check configuration files
echo "3. Configuration Files"

CONFIG_FILES=(
    "configs/sysctl.d/99-marathon.conf"
    "configs/udev.rules.d/60-marathon-cpufreq.rules"
    "configs/udev.rules.d/60-marathon-iosched.rules"
    "configs/systemd/sleep.conf.d/50-marathon.conf"
    "configs/systemd/zram-generator.conf.d/50-marathon.conf"
    "configs/security/limits.d/50-marathon.conf"
)

for file in "${CONFIG_FILES[@]}"; do
    if [ -f "$file" ]; then
        check_pass "$file exists"
    else
        check_fail "$file missing"
    fi
done

echo ""

# 4. Check device configurations
echo "4. Device Configurations"

if [ -f "devices/enchilada/device.conf" ]; then
    check_pass "OnePlus 6 (enchilada) config found"
else
    check_fail "OnePlus 6 (enchilada) config missing"
fi

if [ -f "devices/sdm845/kernel-config.fragment" ]; then
    check_pass "SDM845 SoC config found"
else
    check_fail "SDM845 SoC config missing"
fi

if [ -f "devices/generic/device.conf" ]; then
    check_pass "Generic ARM64 config found"
else
    check_warn "Generic ARM64 config missing"
fi

echo ""

# 5. Check documentation
echo "5. Documentation"

DOCS=(
    "docs/BUILD_THIS.md"
    "docs/DEVICE_SUPPORT.md"
    "docs/KERNEL_CONFIG.md"
    "docs/TROUBLESHOOTING.md"
    "docs/PACKAGE_REFERENCE.md"
    "docs/PERFORMANCE_VALIDATION.md"
    "docs/PRE_BUILD_CHECKLIST.md"
    "docs/FEDORA_SETUP.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        check_pass "$doc exists"
    else
        check_warn "$doc missing (optional)"
    fi
done

echo ""

# 6. Check package definitions
echo "6. Package Definitions"

# Check APKBUILDs have required fields
for pkg in packages/*/APKBUILD; do
    if grep -q "^pkgname=" "$pkg" && \
       grep -q "^pkgver=" "$pkg" && \
       grep -q "^pkgdesc=" "$pkg"; then
        check_pass "$(basename $(dirname $pkg))/APKBUILD has required fields"
    else
        check_fail "$(basename $(dirname $pkg))/APKBUILD missing required fields"
    fi
done

echo ""

# 7. Check for common issues
echo "7. Potential Issues"

# Check for TODO markers
TODO_COUNT=$(grep -r "TODO\|FIXME\|XXX" --exclude-dir=.git --exclude="*.sh" . 2>/dev/null | wc -l)
if [ "$TODO_COUNT" -gt 0 ]; then
    check_warn "Found $TODO_COUNT TODO/FIXME markers in code"
else
    check_pass "No TODO markers found"
fi

# Check file permissions
WORLD_WRITABLE=$(find . -type f -perm -002 ! -path "./.git/*" 2>/dev/null | wc -l)
if [ "$WORLD_WRITABLE" -gt 0 ]; then
    check_warn "Found $WORLD_WRITABLE world-writable files"
else
    check_pass "No world-writable files"
fi

echo ""

# 8. Check symlinks
echo "8. Symlinks"

BROKEN_SYMLINKS=$(find . -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
if [ "$BROKEN_SYMLINKS" -gt 0 ]; then
    check_fail "Found $BROKEN_SYMLINKS broken symlinks"
    find . -type l ! -exec test -e {} \; -print 2>/dev/null | while read link; do
        echo "  - $link"
    done
else
    check_pass "No broken symlinks"
fi

echo ""

# Summary
echo "=== Summary ==="
echo ""
echo -e "  ${COLOR_GREEN}Passed:${COLOR_RESET}  $PASS"
echo -e "  ${COLOR_YELLOW}Warnings:${COLOR_RESET} $WARN"
echo -e "  ${COLOR_RED}Failed:${COLOR_RESET}  $FAIL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${COLOR_GREEN}✓ Repository is ready for building!${COLOR_RESET}"
    echo ""
    echo "Next steps:"
    echo "  1. Review docs/FEDORA_SETUP.md"
    echo "  2. Review docs/PRE_BUILD_CHECKLIST.md"
    echo "  3. Run: ./scripts/build-and-flash.sh <device>"
    echo ""
    exit 0
else
    echo -e "${COLOR_RED}✗ Repository has $FAIL critical issue(s)${COLOR_RESET}"
    echo ""
    echo "Please fix the failed checks before proceeding."
    echo ""
    exit 1
fi


