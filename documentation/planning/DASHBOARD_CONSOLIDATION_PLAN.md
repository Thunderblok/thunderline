# Dashboard Consolidation Plan

## Current State (MESS!)
We have 10+ separate dashboards scattered across the app:

1. `/` → ThunderlineDashboardLive (React hybrid?)
2. `/dashboard` → DashboardLive (Main, has tabs)
3. `/cerebros` → CerebrosLive (ML/NAS)
4. `/dashboard/thunderlane` → ThunderlaneDashboard
5. `/automata` → AutomataLive (CA viz)
6. `/ca-3d` → CaVisualizationLive (3D CA)
7. `/dashboard/trials` → TrialDashboardLive (ML trials)
8. `/dashboard/events` → EventDashboardLive (Event stream)
9. `/metrics` → MetricsLive (System metrics)
10. `/chat` → ChatLive (Chat interface)
11. `/dev/whiteboard` → WhiteboardLive (Dev tool)
12. Plus 13 domain-specific routes (`/thundercore`, `/thunderbit`, etc.)

## Problems
- **Duplication**: Multiple dashboards showing similar info
- **Navigation confusion**: Users don't know where to go
- **Maintenance nightmare**: Changes need to be made in 10+ places
- **Performance**: Loading 10+ LiveViews is heavy
- **Button issues**: Events not properly wired across all dashboards

## Proposed Solution: 2 Main Dashboards

### 1. **Unified Command Center** (`/dashboard`)
**Keep**: `DashboardLive` (already has tabs!)

**Tabs**:
- Overview (current state)
- System (health, metrics)
- Events (real-time event stream)
- Controls (system controls, buttons)
- Domains (grid of 13 domain panels)
- Automata (CA visualization panel)

**Features**:
- Real-time metrics across all domains
- System health monitoring
- Event flow visualization
- System control buttons (restart, safe mode, etc.)
- Quick actions (create room, etc.)

### 2. **ML/AI Hub** (`/ml`)
**Merge**: CerebrosLive + TrialDashboardLive + ML metrics

**Tabs**:
- Neural Search (Cerebros NAS)
- Training (Active trials, metrics)
- Models (Model registry, runs)
- Experiments (HPO, metrics visualization)

**Features**:
- Neural architecture search
- Model training monitoring
- Real-time metrics charts
- Hyperparameter optimization
- MLflow integration

### 3. **Keep Separate (Specialized Tools)**
- `/chat` - ChatLive (distinct UX)
- `/dev/whiteboard` - WhiteboardLive (dev collaboration tool)
- `/c/:community_slug/:channel_slug` - ChannelLive (Discord-style chat)

### 4. **Remove/Deprecate**
- `/` - Redirect to `/dashboard`
- `/dashboard/thunderlane` - Move to tab in main dashboard
- `/ca-3d` - Merge into automata tab
- `/dashboard/events` - Already in main dashboard as tab
- `/metrics` - Already in main dashboard as tab
- 13 domain routes - Become tabs/panels in main dashboard

## Migration Steps

### Phase 1: Fix Buttons (IMMEDIATE)
1. Debug why `create_room` event not firing
2. Test all buttons in Controls tab
3. Add visual feedback (loading states)

### Phase 2: Consolidate ML (Week 1)
1. Create new `/ml` route → MLHubLive
2. Merge CerebrosLive functionality into ML Hub
3. Merge TrialDashboardLive into ML Hub
4. Add tabs for Neural Search, Training, Models
5. Redirect old routes with deprecation notice

### Phase 3: Enhance Main Dashboard (Week 2)
1. Add Domains tab with 13 domain panels (grid layout)
2. Add Automata tab with CA visualization
3. Improve Overview tab with key metrics
4. Remove duplicate routes

### Phase 4: Cleanup (Week 3)
1. Remove deprecated LiveView modules
2. Update router
3. Update documentation
4. Add tests

## Files to Modify

### Keep & Enhance
- `lib/thunderline_web/live/dashboard_live.ex` - Main dashboard
- `lib/thunderline_web/live/dashboard_live.html.heex` - Main template

### Create New
- `lib/thunderline_web/live/ml_hub_live.ex` - Unified ML dashboard
- `lib/thunderline_web/live/ml_hub_live.html.heex` - ML template

### Deprecate/Remove
- `lib/thunderline_web/live/thunderline_dashboard_live.ex`
- `lib/thunderline_web/live/thunderlane_dashboard.ex`
- `lib/thunderline_web/live/ca_visualization_live.ex` (merge into automata)
- `lib/thunderline_web/live/event_dashboard_live.ex` (already in main)
- `lib/thunderline_web/live/metrics_live.ex` (already in main)

### Update
- `lib/thunderline_web/router.ex` - Consolidate routes

## Benefits
- **Single source of truth**: One main dashboard
- **Better UX**: Clear navigation, consistent layout
- **Easier maintenance**: Changes in one place
- **Better performance**: Fewer LiveViews to mount
- **Cleaner codebase**: Less duplication
- **Fixed buttons**: Proper event handling

## Risks
- **Breaking changes**: Old URLs stop working (mitigate with redirects)
- **User confusion**: Need clear migration guide
- **Testing effort**: Need to test consolidated dashboard thoroughly

## Success Criteria
- All buttons work correctly
- Navigation is clear and intuitive
- Performance improves (faster load times)
- Code duplication reduced by 80%+
- All features accessible from 2 main dashboards
