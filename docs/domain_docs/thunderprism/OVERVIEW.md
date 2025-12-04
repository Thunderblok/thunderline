# ThunderPrism Domain Overview

**Vertex Position**: Data Plane Ring — UX & Visualization Surface

**Purpose**: User experience domain managing dashboards, UI state, 3D visualizations, and presentation logic.

## Charter

ThunderPrism is the presentation layer for Thunderline. It manages LiveView components, dashboard state, 3D/WebGL visualizations, and user interface interactions. The domain translates internal system state into visual representations and handles user input that feeds back into the system.

## Core Responsibilities

1. **Dashboard Management** — orchestrate multi-panel dashboard layouts with real-time updates.
2. **3D Graph Visualization** — render node graphs, domain topology, and PAC networks using WebGL/Three.js.
3. **LiveView Components** — provide reusable UI components for Phoenix LiveView.
4. **State Projection** — transform domain events into UI-friendly state representations.
5. **User Input Handling** — capture and route user interactions to appropriate domain actions.

## System Cycle Position

ThunderPrism is a **terminal surface** domain:
- **Upstream**: ThunderGrid (API surface)
- **Downstream**: User interface (external)
- **Domain Vector**: Grid → Prism (IO → surface → UX)

## Ash Resources

| Resource | Purpose |
|----------|---------|
| `Thunderline.Thunderprism.Dashboard` | Dashboard configuration and state |
| `Thunderline.Thunderprism.Panel` | Individual panel definitions |

## Key Modules

- `ThunderlineWeb.Live.*` - LiveView modules for UI
- `Thunderline.Thunderprism.GraphRenderer` - 3D visualization engine

## LiveView Integration

ThunderPrism components follow Phoenix 1.8 conventions:
- Templates use `<Layouts.app flash={@flash}>` wrapper
- Forms use `to_form/2` and `<.input>` components
- Streams for efficient collection rendering

---

*Last Updated: December 2025*
