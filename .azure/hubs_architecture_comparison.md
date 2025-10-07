# Mozilla Hubs Architecture Comparison for Thunderline WebRTC Collab Room

**Date**: 2025-10-07
**Purpose**: Analyze Mozilla Hubs/Reticulum architecture to inform Thunderline WebRTC collaboration room design

---

## Architecture Overview Comparison

### Mozilla Hubs Stack
```
┌─────────────────────────────────────────────────┐
│  Frontend Layer (Node.js)                       │
│  - Hubs Client (WebRTC client, Three.js)        │
│  - Spoke (Scene editor)                         │
│  - Admin Panel (React admin interface)          │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Backend Layer (Elixir/Phoenix)                 │
│  - Reticulum (Phoenix channels, WebRTC signals) │
│  - Dialog (Mediasoup WebRTC SFU)                │
│  - PostgREST (Admin API)                        │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Data Layer                                     │
│  - PostgreSQL (rooms, users, sessions)          │
│  - Storage (assets, files)                      │
│  - Coturn (TURN/STUN servers)                   │
└─────────────────────────────────────────────────┘
```

### Thunderline Current Stack
```
┌─────────────────────────────────────────────────┐
│  Frontend Layer (Phoenix LiveView)              │
│  - LiveView templates (HEEx)                    │
│  - JavaScript hooks (Canvas, AutoScroll)        │
│  - Real-time UI updates                         │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Backend Layer (Elixir/Phoenix)                 │
│  - Phoenix Channels (VoiceChannel)              │
│  - Phoenix Presence (user tracking)             │
│  - GenServers (RoomPipeline)                    │
│  - Ash Framework (domain logic)                 │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│  Data Layer                                     │
│  - PostgreSQL (Ash resources)                   │
│  - PubSub (real-time events)                    │
│  - Oban (background jobs)                       │
└─────────────────────────────────────────────────┘
```

---

## Key Architectural Patterns

### 1. Phoenix Channels for WebRTC Signaling

**Hubs Pattern (hub_channel.ex)**:
```elixir
defmodule RetWeb.HubChannel do
  use RetWeb, :channel
  
  # Join room with authentication
  def join("hub:" <> hub_sid, params, socket) do
    socket = assign(socket, :hub_sid, hub_sid)
    send(self(), {:begin_tracking, session_id, hub_sid})
    {:ok, response, socket}
  end
  
  # WebRTC signaling (NAF = Networked A-Frame)
  def handle_in("naf" = event, payload, socket) do
    broadcast_from!(socket, event, payload_with_from(socket))
    {:noreply, socket}
  end
  
  # Voice/video controls
  def handle_in("mute" = event, payload, socket) do
    broadcast_from!(socket, event, payload)
    {:noreply, socket}
  end
end
```

**Thunderline Equivalent (voice_channel.ex)**:
```elixir
defmodule ThunderlineWeb.VoiceChannel do
  use ThunderlineWeb, :channel
  
  # Already exists! Similar pattern
  def join("voice:" <> room_id, _params, socket) do
    socket = assign(socket, :room_id, room_id)
    # Track presence
    {:ok, socket}
  end
  
  # WebRTC signaling via RoomPipeline
  def handle_in("offer", %{"sdp" => sdp}, socket) do
    RoomPipeline.handle_offer(room_id, principal_id, sdp)
    {:noreply, socket}
  end
end
```

**✅ Thunderline already has this pattern!**

---

### 2. Phoenix Presence for User Tracking

**Hubs Pattern (presence.ex)**:
```elixir
defmodule RetWeb.Presence do
  use Phoenix.Presence,
    otp_app: :ret,
    pubsub_server: Ret.PubSub
  
  # Track session with metadata
  def track(socket, session_id, %{profile: profile, context: context}) do
    Phoenix.Presence.track(socket, session_id, %{
      presence: :room,  # :lobby | :room
      profile: profile,
      context: context,
      roles: roles,
      permissions: permissions
    })
  end
  
  # Count users in room
  def member_count_for(hub_sid) do
    list("hub:#{hub_sid}")
    |> Enum.filter(fn {_, %{metas: m}} ->
      m |> Enum.any?(fn %{presence: p} -> p == :room end)
    end)
    |> Enum.count()
  end
end
```

**Thunderline Equivalent (presence.ex)**:
```elixir
defmodule ThunderlineWeb.Presence do
  use Phoenix.Presence,
    otp_app: :thunderline,
    pubsub_server: Thunderline.PubSub
  
  # Already tracking channels and global presence!
  def track_channel(pid, channel_id, user_id, metadata) do
    track(pid, "channel_presence:#{channel_id}", user_id, metadata)
  end
  
  def track_global(pid, user_id, metadata) do
    track(pid, "presence_global", user_id, metadata)
  end
end
```

**✅ Thunderline already has this pattern!**

---

### 3. Room Management with GenServers

**Hubs Pattern (room_pipeline.ex)**:
```elixir
defmodule Ret.RoomPipeline do
  use GenServer
  
  # One GenServer per room (Registry-based)
  def handle_offer(room_id, principal_id, sdp) do
    GenServer.call(via(room_id), {:handle_offer, principal_id, sdp})
  end
  
  # Broadcast to all participants
  def handle_call({:handle_offer, principal_id, sdp}, _from, state) do
    RetWeb.Endpoint.broadcast("voice:#{room_id}", "webrtc_offer", %{
      from: principal_id,
      sdp: sdp
    })
    {:reply, :ok, state}
  end
end
```

**Thunderline Equivalent (room_pipeline.ex)**:
```elixir
defmodule Thunderline.Thunderlink.Voice.RoomPipeline do
  use GenServer
  
  # Already has identical pattern!
  def handle_offer(room_id, principal_id, sdp) do
    GenServer.call(via(room_id), {:handle_offer, principal_id, sdp})
  end
  
  # Broadcasts WebRTC events
  def handle_call({:handle_offer, principal_id, sdp}, _from, state) do
    Thunderline.PubSub.broadcast("voice:#{room_id}", {:webrtc_offer, principal_id, sdp})
    {:reply, :ok, state}
  end
end
```

**✅ Thunderline already has this pattern!**

---

### 4. Canvas Collaboration (New Pattern from Pete Corey)

**Hubs Pattern (NOT in Hubs - they use 3D)**:
- Hubs uses Three.js for 3D collaboration
- No 2D canvas whiteboard in Hubs

**Pete Corey Pattern (what we want)**:
```elixir
# LiveView
defmodule ThunderlineWeb.WhiteboardLive do
  use ThunderlineWeb, :live_view
  
  def mount(_params, _session, socket) do
    topic = "whiteboard:global"
    ThunderlineWeb.Endpoint.subscribe(topic)
    
    socket = 
      socket
      |> assign(:strokes, [])
      |> stream(:users, [])
    
    {:ok, socket}
  end
  
  def handle_event("stroke", %{"points" => points, "color" => color}, socket) do
    stroke = %{id: UUID.uuid4(), points: points, color: color}
    
    # Broadcast to all users
    ThunderlineWeb.Endpoint.broadcast("whiteboard:global", "new_stroke", stroke)
    
    {:noreply, assign(socket, :strokes, [stroke | socket.assigns.strokes])}
  end
  
  def handle_info(%{event: "new_stroke", payload: stroke}, socket) do
    # Push to canvas hook
    {:noreply, push_event(socket, "draw_stroke", stroke)}
  end
end
```

```javascript
// Canvas Hook (assets/js/hooks/whiteboard.js)
export const Whiteboard = {
  mounted() {
    this.canvas = this.el.querySelector("canvas");
    this.ctx = this.canvas.getContext("2d");
    this.drawing = false;
    this.currentStroke = [];
    
    // Mouse events
    this.canvas.addEventListener("mousedown", (e) => this.startStroke(e));
    this.canvas.addEventListener("mousemove", (e) => this.drawStroke(e));
    this.canvas.addEventListener("mouseup", (e) => this.endStroke(e));
    
    // Handle remote strokes
    this.handleEvent("draw_stroke", ({points, color}) => {
      this.renderStroke(points, color);
    });
  },
  
  startStroke(e) {
    this.drawing = true;
    this.currentStroke = [[e.offsetX, e.offsetY]];
  },
  
  drawStroke(e) {
    if (!this.drawing) return;
    
    const point = [e.offsetX, e.offsetY];
    this.currentStroke.push(point);
    this.renderStroke([this.currentStroke[this.currentStroke.length - 2], point]);
  },
  
  endStroke(e) {
    this.drawing = false;
    
    // Send to server
    this.pushEvent("stroke", {
      points: this.currentStroke,
      color: this.color || "#000"
    });
  },
  
  renderStroke(points, color = "#000") {
    this.ctx.strokeStyle = color;
    this.ctx.lineWidth = 2;
    this.ctx.lineCap = "round";
    
    this.ctx.beginPath();
    this.ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) {
      this.ctx.lineTo(points[i][0], points[i][1]);
    }
    this.ctx.stroke();
  }
};
```

**🆕 This is the new pattern we need to add!**

---

## Infrastructure Comparison

| Component | Mozilla Hubs | Thunderline | Status |
|-----------|-------------|-------------|--------|
| **WebRTC Library** | Mediasoup (Dialog) | ex_webrtc 0.13.0 | ✅ Installed |
| **Phoenix Channels** | HubChannel, VoiceChannel | VoiceChannel | ✅ Exists |
| **Presence Tracking** | RetWeb.Presence | ThunderlineWeb.Presence | ✅ Exists |
| **Room GenServers** | RoomAssigner, RoomPipeline | Voice.RoomPipeline | ✅ Exists |
| **Canvas Rendering** | None (3D only) | CA Visualization | ✅ Pattern exists |
| **Real-time Chat** | Message broadcasting | ChannelLive | ✅ Exists |
| **PubSub** | Phoenix.PubSub | Thunderline.PubSub | ✅ Exists |
| **Database** | PostgreSQL | PostgreSQL (Ash) | ✅ Exists |
| **Admin Interface** | React + PostgREST | Phoenix LiveView | ✅ Better than Hubs! |

---

## What We Can Learn from Hubs

### 1. Session Management
Hubs tracks detailed session stats:
```elixir
# SessionStat tracks entry/exit times, CCU (concurrent users)
def changeset_for_new_session(socket, hub) do
  %SessionStat{}
  |> SessionStat.changeset(%{
    started_at: NaiveDateTime.utc_now(),
    hub_id: hub.hub_id,
    session_id: socket.assigns.session_id
  })
  |> Repo.insert()
end
```

**Thunderline equivalent**: Add to Voice.Participant resource
```elixir
# lib/thunderline/thunderlink/voice/participant.ex
attributes do
  uuid_primary_key :id
  attribute :joined_at, :utc_datetime_usec
  attribute :left_at, :utc_datetime_usec
  attribute :total_duration, :integer  # seconds
  attribute :metadata, :map  # Canvas activity, mic/video state
end
```

### 2. Permissions System
Hubs has granular permissions:
```elixir
# Hub member permissions
@default_member_permissions %{
  spawn_camera: true,
  spawn_drawing: true,
  pin_objects: false,
  fly: true,
  voice_chat: true,
  text_chat: true
}
```

**Thunderline equivalent**: Add to Voice.Room resource
```elixir
# lib/thunderline/thunderlink/voice/room.ex
attributes do
  attribute :permissions, :map do
    default %{
      draw: true,
      chat: true,
      video: true,
      screen_share: true
    }
  end
end
```

### 3. Load Balancing (Future)
Hubs uses RoomAssigner GenServer for distributing rooms across nodes:
```elixir
def pick_host do
  {:ok, host_to_ccu} = Cachex.get(:janus_load_status, :host_to_ccu)
  
  # Find host with lowest CCU (concurrent users)
  host_to_ccu
  |> Enum.min_by(fn {_host, ccu} -> ccu end)
  |> elem(0)
end
```

**Thunderline note**: Not needed yet (single node), but good future reference

---

## Deployment Architecture

### Hubs Production Stack (VPS)
```
System Requirements:
- 8GB+ RAM (Hubs uses ~800MB optimized)
- 2+ CPU cores
- Ubuntu 18.04+

Services:
1. Reticulum (Phoenix) - Port 4000 (Elixir)
2. Dialog (Mediasoup) - Port 4443 (Node.js, pm2)
3. Hubs Client - Port 8080 (webpack-dev-server)
4. Spoke Editor - Port 9090 (webpack-dev-server)
5. Admin Panel - Port 8989 (static nginx)
6. PostgREST - Port 3000 (DB admin API)
7. PostgreSQL - Port 5432
8. Coturn (TURN/STUN) - Ports 3478, 5349

Deployment:
- GitHub Actions self-hosted runners
- Systemd services for auto-restart
- Nginx reverse proxy
- Let's Encrypt SSL
```

### Thunderline Equivalent (Simpler!)
```
System Requirements:
- 4GB+ RAM (LiveView is lighter)
- 2+ CPU cores
- Ubuntu 20.04+

Services:
1. Thunderline (Phoenix) - Port 4000 (includes everything!)
   - LiveView (no separate webpack servers)
   - Channels (WebRTC signaling)
   - Presence (user tracking)
   - Ash API (no PostgREST needed)
2. PostgreSQL - Port 5432
3. Optional: Coturn (if NAT traversal needed)

Deployment:
- Mix release (single binary)
- Systemd service
- Nginx reverse proxy (optional with SSL)
```

**✅ Thunderline is architecturally simpler!**

---

## Performance Notes from Hubs

### Memory Usage
- Base Reticulum: ~800MB RAM
- Dialog (Mediasoup): ~200MB per room
- Total for 5 concurrent rooms: ~1.8GB

### Optimization Strategies
1. **Asset Caching**: Hubs caches 3D models, textures
2. **Connection Pooling**: PostgreSQL pool_size: 10
3. **Presence Optimization**: Only broadcast diffs, not full state
4. **WebRTC Optimization**: Use TURN only as fallback (most users use STUN)

---

## Recommended Architecture for Thunderline Collab Room

### Phase 1: Canvas Whiteboard (Minimal)
```
Components:
1. WhiteboardLive (LiveView)
2. Whiteboard.js hook (Canvas + mouse events)
3. PubSub topic: "whiteboard:global"
4. Presence tracking (already exists)
5. Simple text chat (reuse ChannelLive pattern)

Time: 2-3 hours
Dependencies: None (all infrastructure exists)
```

### Phase 2: WebRTC Video Tiles (Optional)
```
Components:
1. Extend VoiceChannel for video
2. ex_webrtc MediaStream handling
3. Add video tiles to WhiteboardLive sidebar
4. Use existing RoomPipeline for signaling

Time: +2 hours
Dependencies: ex_webrtc (already installed)
```

### Phase 3: Advanced Features (Future)
```
Components:
1. Screen sharing (ex_webrtc supports)
2. Recording (ex_webrtc_recorder installed)
3. File uploads (Ash.Storage integration)
4. Persistent canvas state (save/load drawings)
5. Room history (Ash.Events tracking)

Time: +4-6 hours
Dependencies: Storage configuration, Events setup
```

---

## Key Differences: Hubs vs Thunderline

| Aspect | Mozilla Hubs | Thunderline | Winner |
|--------|-------------|-------------|--------|
| **Complexity** | 5 services, 3 languages | 1 service, 1 language | Thunderline |
| **Real-time** | Channels + NAF protocol | LiveView + Channels | Thunderline (simpler) |
| **Admin UI** | React SPA + PostgREST | Phoenix LiveView | Thunderline (native) |
| **3D Graphics** | Three.js (advanced) | A-Frame (simpler) | Hubs |
| **2D Canvas** | None | Can add easily | Thunderline |
| **State Mgmt** | Client-side (React) | Server-side (LiveView) | Thunderline (safer) |
| **Deployment** | Complex (6+ services) | Simple (1 release) | Thunderline |
| **Learning** | JS + Elixir + React | Elixir + LiveView | Thunderline |

---

## Conclusion: Thunderline is Better Positioned!

### Why Thunderline is Ideal for Collab Room:

1. **Simpler Stack**: Phoenix LiveView = WebRTC signaling + UI in one
2. **Proven Patterns**: Voice infrastructure already exists
3. **Canvas Ready**: CA visualization proves pattern works
4. **No Separate Frontend**: LiveView handles everything
5. **Better State Management**: Server-driven = fewer sync bugs
6. **Easier Deployment**: Single Mix release vs. 5+ services
7. **Native Admin**: LiveView admin vs. React SPA
8. **Ash Framework**: Better than raw Ecto for permissions/resources

### What We Learned from Hubs:

1. ✅ **Session tracking** - Add to Participant resource
2. ✅ **Granular permissions** - Add to Room resource
3. ✅ **Presence patterns** - Already doing it correctly
4. ✅ **Channel patterns** - Already doing it correctly
5. ⏭️ **Load balancing** - Future consideration (multi-node)
6. ⏭️ **TURN fallback** - Optional (most connections work with STUN)

### Recommended Next Steps:

**Option A: Full Dev Collab Room** (~4-5 hours)
- Canvas whiteboard + WebRTC video + chat
- Complete team collaboration solution
- Validates all real-time patterns
- Immediate business value

**Option B: Canvas Whiteboard First** (~2-3 hours) ⭐ RECOMMENDED
- Simpler, faster MVP
- Immediate value (drawing + chat)
- Add video later if needed
- Less risk, faster feedback

**Option C: Finish MLflow Tests** (~3 hours)
- Complete Phase 5 (20% remaining)
- Then build collab room
- More conservative approach

---

## File References

**Hubs Architecture**:
- `HubChannel` - WebRTC signaling, presence, events
- `Presence` - User tracking, CCU counts
- `RoomPipeline` - Per-room GenServer coordination
- `SessionStat` - Analytics and monitoring

**Thunderline Equivalents**:
- `/lib/thunderline_web/channels/voice_channel.ex` - WebRTC signaling ✅
- `/lib/thunderline_web/presence.ex` - User tracking ✅
- `/lib/thunderline/thunderlink/voice/room_pipeline.ex` - Room coordination ✅
- `/lib/thunderline_web/live/ca_visualization_live.ex` - Canvas pattern ✅
- `/lib/thunderline_web/live/channel_live.ex` - Chat pattern ✅

**To Be Created**:
- `/lib/thunderline_web/live/whiteboard_live.ex` - Canvas whiteboard LiveView
- `/assets/js/hooks/whiteboard.js` - Canvas drawing hook
- Optional: `/lib/thunderline/thunderlink/voice/session_stat.ex` - Analytics

---

**Assessment**: Thunderline has **ALL** infrastructure needed for WebRTC collaboration room. The architecture is **simpler and better** than Mozilla Hubs for our use case. We should proceed with **Option B** (Canvas whiteboard first), then add video if needed.

