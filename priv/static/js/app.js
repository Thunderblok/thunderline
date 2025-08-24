// Unbundled LiveView bootstrap (Option A no-node)
(() => {
    const phoenix = window.Phoenix || {};
    const lvNS = window.LiveView || {};
    const { Socket } = phoenix;
    const { LiveSocket } = lvNS;
    if (!Socket || !LiveSocket) {
        console.error("Phoenix/LiveView globals not found. Check CDN script tag order.");
        return;
    }

    const Hooks = {
        AutoScroll: {
            mounted() { this.scrollToBottom(); },
            updated() { this.scrollToBottom(); },
            scrollToBottom() { try { this.el.scrollTop = this.el.scrollHeight; } catch (_) { } }
        }
    };

    const csrfTokenEl = document.querySelector("meta[name='csrf-token']");
    if (!csrfTokenEl) {
        console.warn("CSRF meta tag missing");
    }
    const csrfToken = csrfTokenEl ? csrfTokenEl.getAttribute("content") : null;
    const liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken }, hooks: Hooks });

    liveSocket.connect();
    window.liveSocket = liveSocket;
})();
