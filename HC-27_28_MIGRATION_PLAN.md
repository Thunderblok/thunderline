# HC-27/HC-28: ThunderCom to ThunderLink Consolidation Plan

**Date**: November 17, 2025  
**Status**: Planning Phase  
**Priority**: P0 (Launch-Critical)  
**Estimated Effort**: 3-5 days  

## Executive Summary

Complete the incomplete ThunderCom → ThunderLink consolidation by migrating 8 resources, resolving 5 duplicates, and removing the ThunderCom domain. This will eliminate resource duplication, clarify ownership, and complete the domain architecture cleanup started in HC-26.

## Current State (Ground Truth Verified)

### ThunderCom Domain (TO BE REMOVED)
**Location**: `lib/thunderline/thundercom/`  
**Status**: Still active with 8 resources

**8 Resources in ThunderCom**:
1. `Community` (854 lines) - **DUPLICATE** ⚠️
2. `Channel` (805 lines) - **DUPLICATE** ⚠️
3. `Message` (941 lines) - **DUPLICATE** ⚠️
4. `Role` (883 lines) - **DUPLICATE** ⚠️
5. `FederationSocket` (989 lines) - **DUPLICATE** ⚠️
6. `VoiceRoom` (201 lines) - **Voice namespace mismatch** ⚠️
7. `VoiceParticipant` (202 lines) - **Voice namespace mismatch** ⚠️
8. `VoiceDevice` (89 lines) - **Voice namespace mismatch** ⚠️

**Supporting Modules** (4 files):
- `domain.ex` - Ash domain definition
- `notifications.ex` - Notification helpers
- `mailer.ex` - Email functionality
- `voice/supervisor.ex` - Voice pipeline supervisor
- `voice/room_pipeline.ex` - Voice room GenServer
- `calculations/host_participant_id.ex` - Calculation module

### ThunderLink Domain (CANONICAL)
**Location**: `lib/thunderline/thunderlink/`  
**Status**: Target domain for consolidation (17 resources)

**5 Duplicate Resources in ThunderLink**:
1. `Community` (839 lines) - Nearly identical to ThunderCom version
2. `Channel` (790 lines) - Nearly identical
3. `Message` (927 lines) - Nearly identical
4. `Role` (883 lines) - Identical line count
5. `FederationSocket` (978 lines) - Nearly identical

**3 Voice Resources** (Different namespace):
1. `Voice.Room` (163 lines) - **Has deprecation notice for ThunderCom.VoiceRoom**
2. `Voice.Participant` - Matches ThunderCom.VoiceParticipant
3. `Voice.Device` - Matches ThunderCom.VoiceDevice

**Key Difference**: 
- ThunderCom uses `Resources.VoiceRoom` (flat namespace)
- ThunderLink uses `Voice.Room` (nested namespace)
- ThunderLink.Voice.Room already has deprecation notice: "DEPRECATION: Thunderline.Thundercom.Resources.VoiceRoom will be removed after grace cycle"

### Active Usage

**LiveViews Referencing ThunderCom** (2 files):
1. `lib/thunderline_web/live/community_live.ex`
   - Uses: `Thunderline.Thundercom.Resources.{Community, Channel}`
   - Uses: `Thunderline.Thundercom.Domain`

2. `lib/thunderline_web/live/channel_live.ex`
   - Uses: `Thunderline.Thundercom.Resources.{Community, Channel, Message}`
   - Uses: `Thunderline.Thundercom.Domain`

**Seeds**: No seed files reference ThunderCom (grep found zero matches)

**GraphQL**: ThunderLink domain has GraphQL configured, ThunderCom does not

## Key Findings

### 1. Duplicate Resources Are Nearly Identical
- **Line count comparison**: Community (854 vs 839), Channel (805 vs 790), Message (941 vs 927), Role (883 vs 883), FederationSocket (989 vs 978)
- **Key difference**: ThunderCom resources have `authorizers: [Ash.Policy.Authorizer]`, ThunderLink resources do NOT (policies removed in "WARHORSE" governance refactor)
- **Database tables**: Both point to same tables (e.g., `thunderblock_communities`)
- **Recommendation**: **ThunderLink versions are canonical** (newer migration target, GraphQL configured, part of intended architecture)

### 2. Voice Resources Already Migrated (Partially)
- ThunderLink.Voice.Room **already exists** and has deprecation notice for ThunderCom.VoiceRoom
- Voice namespace properly nested in ThunderLink (`Voice.Room` not `Resources.VoiceRoom`)
- **Action**: Remove ThunderCom voice resources (VoiceRoom, VoiceParticipant, VoiceDevice)

### 3. LiveViews Need Simple Update
- Only 2 LiveView files reference ThunderCom
- Simple alias updates: `Thunderline.Thundercom.Resources.X` → `Thunderline.Thunderlink.Resources.X`
- Domain change: `Thunderline.Thundercom.Domain` → `Thunderline.Thunderlink.Domain`

### 4. Supporting Modules Need Relocation
- `notifications.ex`, `mailer.ex` - Determine if still needed or if duplicated elsewhere
- `voice/supervisor.ex`, `voice/room_pipeline.ex` - Check if duplicated in ThunderLink
- `calculations/host_participant_id.ex` - May need to move to ThunderLink

## Migration Strategy

### Phase 1: Pre-Migration Verification (Day 1 - 2 hours)
**Goal**: Ensure we understand all dependencies before making changes

✅ **Tasks**:
1. ✅ Verify ThunderCom and ThunderLink resource lists
2. ✅ Identify all LiveView references
3. ✅ Check seed file dependencies
4. ✅ Compare duplicate resource implementations
5. **TODO**: Check for ThunderCom references in tests
6. **TODO**: Verify supporting modules (notifications, mailer, voice supervisor)
7. **TODO**: Check GraphQL/RPC definitions
8. **TODO**: Verify no other modules alias ThunderCom

### Phase 2: Update LiveViews (Day 1 - 2 hours)
**Goal**: Switch LiveViews to use ThunderLink resources

**Files to Update** (2 files):
1. `lib/thunderline_web/live/community_live.ex`
2. `lib/thunderline_web/live/channel_live.ex`

**Changes**:
```elixir
# OLD
alias Thunderline.Thundercom.Resources.{Community, Channel, Message}
alias Thunderline.Thundercom.Domain

# NEW
alias Thunderline.Thunderlink.Resources.{Community, Channel, Message}
alias Thunderline.Thunderlink.Domain
```

### Phase 3: Remove Duplicate Resources from ThunderCom (Day 2 - 4 hours)
**Goal**: Remove the 5 duplicate resources from ThunderCom domain

**Resources to Remove**:
1. `lib/thunderline/thundercom/resources/community.ex` (854 lines)
2. `lib/thunderline/thundercom/resources/channel.ex` (805 lines)
3. `lib/thunderline/thundercom/resources/message.ex` (941 lines)
4. `lib/thunderline/thundercom/resources/role.ex` (883 lines)
5. `lib/thunderline/thundercom/resources/federation_socket.ex` (989 lines)

**Update ThunderCom domain.ex**: Remove these 5 resources from the `resources do` block

### Phase 4: Remove Voice Resources from ThunderCom (Day 2 - 2 hours)
**Goal**: Remove ThunderCom voice resources (already migrated to ThunderLink.Voice)

**Resources to Remove**:
1. `lib/thunderline/thundercom/resources/voice_room.ex` (201 lines)
2. `lib/thunderline/thundercom/resources/voice_participant.ex` (202 lines)
3. `lib/thunderline/thundercom/resources/voice_device.ex` (89 lines)

**Update ThunderCom domain.ex**: Remove these 3 resources from the `resources do` block

**Note**: ThunderLink.Voice.Room already has deprecation notice, so this is the final removal step

### Phase 5: Handle Supporting Modules (Day 3 - 3 hours)
**Goal**: Relocate or verify supporting modules

**Files to Investigate**:
1. `lib/thunderline/thundercom/notifications.ex` - Check if duplicated in ThunderLink
2. `lib/thunderline/thundercom/mailer.ex` - Check if duplicated in ThunderLink
3. `lib/thunderline/thundercom/voice/supervisor.ex` - Check if needed after voice resource removal
4. `lib/thunderline/thundercom/voice/room_pipeline.ex` - Check if needed
5. `lib/thunderline/thundercom/calculations/host_participant_id.ex` - Move to ThunderLink if still needed

**Decision Matrix**:
- If module has duplicate in ThunderLink → Remove from ThunderCom
- If module is unique and still needed → Move to ThunderLink
- If module is obsolete → Remove entirely

### Phase 6: Remove ThunderCom Domain (Day 3 - 2 hours)
**Goal**: Complete removal of ThunderCom domain

**Steps**:
1. Verify ThunderCom domain.ex has zero resources registered
2. Delete entire `lib/thunderline/thundercom/` directory
3. Verify no compilation errors
4. Run tests to ensure no breakage

### Phase 7: Update Documentation (Day 3 - 2 hours)
**Goal**: Document the consolidation completion

**Files to Update**:
1. `THUNDERLINE_MASTER_PLAYBOOK.md` - Mark HC-27 and HC-28 complete
2. `THUNDERLINE_DOMAIN_CATALOG.md` - Remove ThunderCom section, update ThunderLink
3. Update HC-26 consolidation count (6 → 7 consolidations)
4. Create migration completion report (like HC-29_COMPLETION_REPORT.md)

### Phase 8: Final Verification (Day 4-5 - 4 hours)
**Goal**: Comprehensive testing and validation

**Verification Steps**:
1. `mix compile --force` - Zero errors expected
2. Run test suite - No new failures
3. Test LiveViews manually (community_live, channel_live)
4. Verify GraphQL API still works
5. Check for any stray ThunderCom references (`grep -r "Thundercom"`)
6. Verify voice functionality if applicable
7. Review git diff for unintended changes

## Risk Assessment

### Low Risk ✅
- **LiveView updates**: Only 2 files, straightforward alias changes
- **Voice resource removal**: Already deprecated, migration target exists
- **Duplicate removal**: Resources are nearly identical, same database tables

### Medium Risk ⚠️
- **Supporting module relocation**: Need to verify if duplicates exist or if modules are obsolete
- **Test breakage**: Tests may reference ThunderCom directly
- **GraphQL/RPC**: Need to verify no ThunderCom resources exposed via API

### High Risk 🔴
- **None identified** - Consolidation is well-understood, no complex migrations

## Rollback Plan

If critical issues are found:
1. **Before Phase 6** (domain removal): Simple - revert file changes via git
2. **After Phase 6**: Restore `lib/thunderline/thundercom/` from git history
3. **LiveViews**: Revert alias changes
4. **No database changes**: All resources use same tables, zero migration risk

## Success Criteria

✅ **Technical Success**:
1. Zero resources remain in ThunderCom domain
2. `lib/thunderline/thundercom/` directory removed
3. LiveViews use ThunderLink resources
4. Compilation successful (zero errors)
5. Test suite passes (no new failures)
6. No stray ThunderCom references in codebase

✅ **Documentation Success**:
1. HC-27 marked ✅ COMPLETE in playbook
2. HC-28 marked ✅ COMPLETE in playbook
3. HC-26 consolidation count updated (7 total)
4. Domain catalog updated (ThunderCom removed)
5. Migration completion report created

## Timeline Estimate

| Phase | Duration | Complexity | Risk |
|-------|----------|------------|------|
| 1. Pre-Migration Verification | 2 hours | Low | Low |
| 2. Update LiveViews | 2 hours | Low | Low |
| 3. Remove Duplicate Resources | 4 hours | Low | Low |
| 4. Remove Voice Resources | 2 hours | Low | Low |
| 5. Handle Supporting Modules | 3 hours | Medium | Medium |
| 6. Remove ThunderCom Domain | 2 hours | Low | Low |
| 7. Update Documentation | 2 hours | Low | Low |
| 8. Final Verification | 4 hours | Low | Low |
| **Total** | **21 hours** | **~3 days** | **Low-Medium** |

**Buffer**: +2 days for unexpected issues = **3-5 days total estimate**

## Next Steps

**Immediate Actions**:
1. Review this migration plan with team/user
2. Get approval to proceed
3. Create feature branch: `hc-27-28-thundercom-consolidation`
4. Begin Phase 1 verification

**Questions to Resolve**:
- Are there any critical ThunderCom features we missed?
- Should we preserve any ThunderCom-specific behavior?
- Any concerns about voice namespace migration?
- Timeline constraints or deadline considerations?

## Notes

- This consolidation was originally assumed complete in HC review (Aug 2025)
- Ground truth verification (Nov 17, 2025) revealed it was incomplete
- Voice resources already have migration path (ThunderLink.Voice namespace)
- LiveViews are the primary active usage (only 2 files)
- No seed files reference ThunderCom (migration easier than expected)
- Duplicate resources use same database tables (zero schema migration needed)

---

**Migration Plan Status**: Ready for Execution  
**Next Action**: User approval → Begin Phase 1
