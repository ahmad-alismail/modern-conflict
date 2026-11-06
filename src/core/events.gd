extends Node
## Global UI-level event bus. Simulation events flow through SimWorld.events
## (polled by the session); this bus is only for app-level navigation and notices.

## Show a transient notice in whichever UI is active. kind: info | warn | alert | good
signal notice(text: String, kind: String)
## Request to switch the top-level screen (handled by Main). params is screen-specific.
signal navigate(screen: String, params: Dictionary)
