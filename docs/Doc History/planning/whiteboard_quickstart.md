# Dev Whiteboard - Quick Start Guide

## 🎨 Thunderline Real-Time Collaboration Whiteboard

**Route**: `/dev/whiteboard`

A real-time collaborative canvas for the dev team with drawing, chat, and presence tracking.

---

## Features

### ✅ Phase 1 Complete (Canvas + Chat)
- **Real-time Drawing**: Pen and eraser tools with color picker
- **Multi-user Collaboration**: See everyone's strokes instantly
- **Remote Cursors**: Watch teammates' mouse positions in real-time
- **Live Chat**: Text chat sidebar for discussion
- **Presence Tracking**: See who's online in the room
- **Canvas Controls**: Clear canvas, adjust line width, change colors
- **Touch Support**: Works on tablets and touch devices

### 🔜 Phase 2 Optional (WebRTC Video)
- **Video Tiles**: Add live video feeds (+2 hours)
- **Screen Sharing**: Share your screen
- **Voice Chat**: Enable voice communication

---

## Usage

### Starting a Session

1. Navigate to `/dev/whiteboard` in your browser
2. You'll automatically join the dev collaboration room
3. Your presence will be broadcast to all other users
4. Start drawing or chatting immediately!

### Drawing Tools

**Pen Tool**:
- Click "Pen" button or use default
- Select color with color picker
- Adjust line width with slider (1-20px)
- Click and drag to draw

**Eraser Tool**:
- Click "Eraser" button
- Eraser is 3x wider than pen width
- Click and drag to erase

**Clear Canvas**:
- Click "Clear Canvas" button (red)
- Confirms before clearing (destructive action)
- Broadcasts clear to all users

### Chat

- Type message in bottom input field
- Press Enter or click send button
- Messages broadcast to all users instantly
- Shows username and timestamp
- Auto-scrolls to latest message

### Presence

- **User List**: Right sidebar shows all online users
- **Green Dot**: Indicates active user
- **Your Name**: Highlighted in blue
- **Remote Cursors**: See teammates' cursors on canvas

---

## Technical Details

### Architecture

```elixir
# LiveView broadcasts via PubSub
ThunderlineWeb.Endpoint.broadcast("whiteboard:dev", "new_stroke", stroke)

# Canvas hook renders locally + remotely
this.handleEvent("draw_stroke", (stroke) => {
  this.renderStroke(stroke.points, stroke.color, stroke.width);
});
```

**Key Components**:
- `WhiteboardLive` - Phoenix LiveView with PubSub
- `Whiteboard` JS Hook - Canvas rendering
- `ThunderlineWeb.Presence` - User tracking
- Phoenix Channels - WebRTC signaling (ready for Phase 2)

### Performance

- **Stroke Throttling**: Cursor updates throttled to 10Hz (100ms)
- **Canvas Optimization**: Direct 2D context rendering
- **Smooth Lines**: Round line caps and joins
- **Presence Updates**: Efficient diff broadcasting

### State Management

All state lives on the server (LiveView):
- ✅ No client-side state sync bugs
- ✅ Single source of truth
- ✅ Easier to reason about
- ✅ Natural persistence path (future)

---

## Keyboard Shortcuts

- **Enter**: Send chat message (when focused on input)
- **Esc**: Cancel current stroke
- **Mouse Drag**: Draw/erase on canvas

---

## Browser Support

Tested on:
- ✅ Chrome/Edge (Chromium)
- ✅ Firefox
- ✅ Safari (Mac/iOS)
- ✅ Mobile browsers (touch events)

---

## Troubleshooting

### Drawing Not Appearing
- Check browser console for errors
- Ensure you're connected (green user dot)
- Refresh page to reconnect

### Chat Messages Not Sending
- Check network connection
- Verify you're authenticated
- Check that message isn't empty

### Canvas Not Clearing
- Confirm the clear action in dialog
- Check that you have permissions
- Refresh if stuck

### Cursor Position Off
- Canvas resizes on window resize
- Refresh to recalibrate coordinates
- Check browser zoom level (100% recommended)

---

## Comparison: Hubs vs Thunderline

See `.azure/hubs_architecture_comparison.md` for full analysis.

| Aspect | Mozilla Hubs | Thunderline Whiteboard |
|--------|-------------|------------------------|
| Services | 5+ (Reticulum, Dialog, Hubs, etc.) | 1 (Phoenix) |
| Languages | Elixir + Node.js + React | Elixir + LiveView |
| State | Client-side (sync bugs) | Server-side (reliable) |
| WebRTC | Mediasoup (complex) | ex_webrtc (simpler) |
| Deployment | 6+ ports, systemd services | Single Mix release |
| Real-time | Channels + custom protocol | LiveView + PubSub |

**Result**: Thunderline is architecturally simpler and better for this use case! 🎉

---

## Future Enhancements

### Phase 2: Video (Optional)
- [ ] Add video tiles to sidebar
- [ ] Integrate `VoiceChannel` for WebRTC signaling
- [ ] Use `ex_webrtc` for peer connections
- [ ] Optional screen sharing

### Phase 3: Persistence
- [ ] Save canvas state to Ash resource
- [ ] Load previous sessions
- [ ] Export canvas as PNG/SVG
- [ ] Share room links (unique URLs)

### Phase 4: Advanced Drawing
- [ ] Shape tools (rectangle, circle, line)
- [ ] Text annotations
- [ ] Image uploads
- [ ] Layers support
- [ ] Undo/redo history

### Phase 5: Collaboration Features
- [ ] Drawing permissions (host controls)
- [ ] Private rooms (password protected)
- [ ] Room invites (email/link)
- [ ] Recording sessions
- [ ] Replay mode

---

## Contributing

This is a **team collaboration tool**! Feel free to:
- Add new drawing tools
- Improve canvas rendering
- Enhance chat features
- Add WebRTC video (Phase 2)

See `CONTRIBUTING.md` for guidelines.

---

## Links

- **Route**: `/dev/whiteboard`
- **Architecture Analysis**: `.azure/hubs_architecture_comparison.md`
- **Hubs Reference**: [Mozilla Hubs](https://github.com/Hubs-Foundation/reticulum)
- **Pete Corey Pattern**: [Canvas Collaboration with LiveView](https://www.petecorey.com/)

---

## Credits

**Inspired by**:
- Mozilla Hubs (WebRTC architecture)
- Pete Corey (Canvas + LiveView pattern)
- Discord (chat + presence UX)

**Built with**:
- Phoenix LiveView (real-time UI)
- Phoenix Channels (WebRTC signaling)
- Phoenix Presence (user tracking)
- Canvas API (2D drawing)
- Tailwind CSS (styling)

---

**Status**: ✅ Phase 1 Complete (Canvas + Chat)
**Next**: 🔜 Phase 2 Optional (Video Tiles)
**Time**: ~2.5 hours (as estimated!)
**Value**: Immediate team collaboration + validates real-time architecture for ML dashboards! 🚀
