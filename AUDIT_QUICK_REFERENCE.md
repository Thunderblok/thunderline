# Audit Quick Reference Card

> **Before auditing**: Read [HOW_TO_AUDIT.md](HOW_TO_AUDIT.md) in full.

## ⚡ Quick Start (10 minutes)

```bash
# 1. Baseline from catalog
cat THUNDERLINE_DOMAIN_CATALOG.md | grep "Total:"

# 2. Count all domains
ls -1 lib/thunderline/ | grep -v ".ex$" | wc -l

# 3. Run batch audit
./audit_all_domains.sh > audit_$(date +%Y%m%d).txt

# 4. Compare results
diff <(grep "Total:" THUNDERLINE_DOMAIN_CATALOG.md) <(cat audit_$(date +%Y%m%d).txt)
```

## 🚨 Golden Rule

**NEVER use GitHub search alone for audits.**

❌ GitHub search shows: file names, line counts, commit dates  
✅ File-by-file audit reveals: production integration, test coverage, cross-domain usage

## 📋 Essential Commands

```bash
# Count resources in a domain
find lib/thunderline/DOMAIN/resources -name "*.ex" -type f 2>/dev/null | wc -l

# Check cross-domain references (production proof)
grep -r "alias Thunderline\.DOMAIN\." lib/thunderline/ --include="*.ex" | \
  grep -v "lib/thunderline/DOMAIN/" | wc -l

# Find saga files (ThunderBolt specific)
find lib/thunderline/DOMAIN -path "*/sagas/*.ex" -type f 2>/dev/null

# Check saga complexity (>100 lines = substantial)
wc -l lib/thunderline/DOMAIN/sagas/*.ex 2>/dev/null

# Verify test coverage
find test -path "*DOMAIN*" -name "*.exs" -type f 2>/dev/null | wc -l

# Check telemetry (production indicator)
grep -r "telemetry" lib/thunderline/DOMAIN/ --include="*.ex" | wc -l
```

## ✅ Production Checklist

Domain is **PRODUCTION** if it has:

- [ ] Multiple substantial files (>100 lines)
- [ ] Cross-domain integration (referenced by 3+ domains)
- [ ] Supervision tree inclusion
- [ ] Comprehensive telemetry
- [ ] Test coverage (integration tests, not just unit)
- [ ] Active usage (called by recent code)

Domain is **EXPERIMENTAL** if:

- [ ] Files named "demo", "example", "poc"
- [ ] No cross-domain references
- [ ] Minimal/no test coverage
- [ ] Missing telemetry
- [ ] Not in supervision tree

## 🎯 4-Step Process

### 1. Count Resources (30 min)
```bash
for d in lib/thunderline/*/; do
  name=$(basename "$d")
  count=$(find "$d/resources" -name "*.ex" -type f 2>/dev/null | wc -l)
  echo "$name: $count resources"
done
```

### 2. Assess Production Status (45 min)
For each domain:
- Read `domain.ex`
- Check saga files (if applicable)
- Count cross-domain references
- Verify test coverage
- Check telemetry integration

### 3. Document Findings (30 min)
Create `CODEBASE_AUDIT_YYYY_MM.md` with:
- Resource count corrections
- Ghost domains discovered
- Production status classifications
- Evidence for each classification

### 4. Update Catalog (15 min)
Apply corrections to `THUNDERLINE_DOMAIN_CATALOG.md`

## 🚫 Common Mistakes

### ❌ The GitHub Search Mistake
**Problem**: Can't assess production status from search results  
**Solution**: Read actual code files, check cross-domain usage

### ❌ The Name Bias Error
**Problem**: "demo" in name = experimental (wrong!)  
**Solution**: Check if it's called by production code

### ❌ The Line Count Fallacy
**Problem**: Small file = experimental (wrong!)  
**Solution**: Check WHAT it does and WHERE it's used

### ❌ The Isolation Assumption
**Problem**: Few imports = not production (wrong!)  
**Solution**: Check imports RELATIVE to domain purpose

## 📊 Batch Audit Script

**Ready to use:** `./audit_all_domains.sh` is executable and available in project root.

```bash
# Run comprehensive audit and save to timestamped file
./audit_all_domains.sh > audit_report_$(date +%Y%m%d).txt

# Quick scan to terminal
./audit_all_domains.sh

# Check specific domain
./audit_all_domains.sh | grep -A 10 "thunderbolt"
```

**Script also documented in `HOW_TO_AUDIT.md` section 7.**

## ⏱️ Time Estimates

- Quick scan: 30 minutes
- Full audit (7-11 domains): 2-3 hours
- Comprehensive audit with documentation: 4-6 hours

## 📞 When In Doubt

1. Read [HOW_TO_AUDIT.md](HOW_TO_AUDIT.md) again
2. Mark as "NEEDS REVIEW" and get team input
3. Run the application to verify domain works
4. Check git history for context
5. Review test files for intent clues

---

**Remember**: A quick GitHub search audit can incorrectly classify production code as experimental. Take the time to do it right. 🎯

**See**: [HOW_TO_AUDIT.md](HOW_TO_AUDIT.md) for full methodology
