defmodule ThunderlineWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ThunderlineWeb, :html

  # NOTE: embed_templates removed to prevent conflicts with dashboard layout function
  # The dashboard uses explicit function definitions for precise control

  @doc """
  Renders the root layout.
  This replaces the embedded root.html.heex template.
  """
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title default="Thunderline" suffix=" · Phoenix Framework">
          {assigns[:page_title]}
        </.live_title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
        <script>
          (() => {
            const setTheme = (theme) => {
              if (theme === "system") {
                localStorage.removeItem("phx:theme");
                document.documentElement.removeAttribute("data-theme");
              } else {
                localStorage.setItem("phx:theme", theme);
                document.documentElement.setAttribute("data-theme", theme);
              }
            };
            if (!document.documentElement.hasAttribute("data-theme")) {
              setTheme(localStorage.getItem("phx:theme") || "system");
            }
            window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"));

            window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme));
          })();
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {@inner_content}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the dashboard layout for the Thunderprism command center.
  This is a minimal root layout that just renders the content without extra navigation.
  """
  def dashboard(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme="thunderline">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <.live_title default="Thunderdash">
          {assigns[:page_title]}
        </.live_title>
        <!-- Unified compiled bundle (no CDN duplication) -->
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}></script>
      </head>
      <body class="min-h-screen bg-black text-neutral-content relative">
        <!-- Global background lines layer (restored) -->
        <div class="absolute inset-0 -z-10 pointer-events-none">
          <svg viewBox="0 0 1600 900" class="w-full h-full">
            <defs>
              <linearGradient id="wire-bg" x1="0" x2="1">
                <stop offset="0%" stop-color="#6366f1" stop-opacity="0.5" />
                <stop offset="50%" stop-color="#22d3ee" stop-opacity="0.5" />
                <stop offset="100%" stop-color="#ec4899" stop-opacity="0.5" />
              </linearGradient>
            </defs>
            <g stroke="url(#wire-bg)" stroke-width="2" fill="none" opacity="0.35">
              <%= for i <- 0..14 do %>
                <line x1="40" y1={60 + i * 52} x2="1560" y2={40 + i * 52} />
              <% end %>
            </g>
          </svg>
        </div>
        <div class="relative z-10">
          <!-- DASHBOARD_LAYOUT_SENTINEL -->
          <!-- Canary badge (remove after verification) -->
          <div class="fixed top-2 left-2 text-[10px] px-2 py-1 rounded bg-emerald-600/80">bundle:compiled</div>
          {@inner_content}
        </div>
      </body>
    </html>
    """
  end

  # Use flash_group from CoreComponents - removed local definition to avoid conflict

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
