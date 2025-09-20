# MCP over Ash (skeleton)

Goal: Treat MCP as GraphQL gateway over Ash resources, with policy in loop.

- Inject actor/tenant from MCP session; deny by default.
- Resolver adapter: AshGraph.resolve(resource, action, args, actor)
- Emit audit events to Flow: audit.resource.read, audit.action.run
