# ThunderVine GraphQL API Documentation

## Overview

ThunderVine domain exposes workflow orchestration capabilities via GraphQL API with comprehensive role-based access control.

## API Configuration

- **Authorization**: Enabled (`authorize? true`)
- **Endpoint**: `/api/graphql`
- **Schema**: Included in `ThunderlineWeb.GraphqlSchema`

## Available Queries

### Workflow Queries

```graphql
# Get single workflow by ID
query {
  workflow(id: "uuid") {
    id
    correlationId
    status
    sourceDomain
    rootEventName
    metadata
    insertedAt
    sealedAt
  }
}

# List all workflows
query {
  workflows {
    id
    correlationId
    status
    sourceDomain
  }
}

# Get workflow by correlation ID
query {
  workflowByCorrelation(correlationId: "your-correlation-id") {
    id
    correlationId
    status
  }
}
```

### WorkflowNode Queries

```graphql
# List all workflow nodes
query {
  workflowNodes {
    id
    workflowId
    nodeType
    sourceName
    status
    startedAt
    completedAt
  }
}
```

### WorkflowLink Queries

Note: Resource type is `WorkflowLink` (renamed from `WorkflowEdge` to avoid GraphQL collision with Relay edge types)

```graphql
# List all workflow links
query {
  workflowEdges {
    id
    workflowId
    fromNodeId
    toNodeId
    edgeType
    insertedAt
  }
}
```

### WorkflowSnapshot Queries

```graphql
# Get single snapshot by ID
query {
  workflowSnapshot(id: "uuid") {
    id
    workflowId
    snapshotType
    correlationId
    metadata
    nodesPayload
    capturedAt
  }
}

# List all snapshots
query {
  workflowSnapshots {
    id
    workflowId
    snapshotType
    capturedAt
  }
}
```

## Available Mutations

### Workflow Mutations

```graphql
# Start a new workflow
mutation {
  startWorkflow(input: {
    sourceDomain: THUNDERVINE
    rootEventName: "workflow.started"
    correlationId: "unique-correlation-id"
    metadata: {key: "value"}
  }) {
    result {
      id
      correlationId
      status
    }
  }
}

# Seal a workflow (mark as complete)
mutation {
  sealWorkflow(id: "workflow-uuid") {
    result {
      id
      status
      sealedAt
    }
  }
}

# Update workflow metadata
mutation {
  updateWorkflowMetadata(id: "workflow-uuid", metadata: {newKey: "newValue"}) {
    result {
      id
      metadata
    }
  }
}
```

### WorkflowNode Mutations

```graphql
# Record node start
mutation {
  recordNodeStart(input: {
    workflowId: "workflow-uuid"
    nodeType: EVENT
    sourceName: "event.name"
    eventId: "event-uuid"
    payload: {data: "value"}
  }) {
    result {
      id
      status
      startedAt
    }
  }
}

# Mark node success
mutation {
  markNodeSuccess(id: "node-uuid", completionPayload: {result: "success"}) {
    result {
      id
      status
      completedAt
    }
  }
}

# Mark node error
mutation {
  markNodeError(id: "node-uuid", errorPayload: {error: "description"}) {
    result {
      id
      status
      completedAt
    }
  }
}
```

### WorkflowLink Mutations

```graphql
# Create workflow edge (dependency)
mutation {
  createWorkflowEdge(input: {
    workflowId: "workflow-uuid"
    fromNodeId: "source-node-uuid"
    toNodeId: "target-node-uuid"
    edgeType: CAUSAL  # or FOLLOWS, CHILD
  }) {
    result {
      id
      edgeType
      insertedAt
    }
  }
}
```

### WorkflowSnapshot Mutations

```graphql
# Capture workflow snapshot
mutation {
  captureWorkflowSnapshot(input: {
    workflowId: "workflow-uuid"
    snapshotType: SEALED
    metadata: {version: "1.0"}
  }) {
    result {
      id
      snapshotType
      capturedAt
    }
  }
}
```

## Authorization & Access Control

### Role-Based Policies

All ThunderVine resources implement comprehensive role-based access control:

**Admin Access (Bypass All Policies)**:
- Actor with `role: :admin` has full access to all operations

**System Access (Bypass All Policies)**:
- Actor with `role: :system` has full access to all operations

**Authenticated User Access**:
- All mutations require authentication (`AshAuthentication.Checks.Authenticated`)
- All read queries require authentication
- Exception: Sealed workflows have public read access

### Example Authenticated Request

```graphql
# Request headers
{
  "Authorization": "Bearer <your-auth-token>",
  "Content-Type": "application/json"
}

# Query
query {
  workflows {
    id
    correlationId
  }
}
```

## GraphQL Type Names

| Resource | GraphQL Type | Notes |
|----------|--------------|-------|
| Workflow | `Workflow` | Standard naming |
| WorkflowNode | `WorkflowNode` | Standard naming |
| WorkflowEdge | `WorkflowLink` | Renamed to avoid GraphQL collision |
| WorkflowSnapshot | `WorkflowSnapshot` | Standard naming |

**Important**: `WorkflowEdge` resource has GraphQL type `WorkflowLink` to avoid collision with AshGraphql's automatic generation of Relay connection edge types (which append `_edge` to type names).

## Error Handling

GraphQL errors follow standard Ash error classes:

- **Forbidden** (`Ash.Error.Forbidden`): Authorization failure
- **Invalid** (`Ash.Error.Invalid`): Validation errors
- **Framework** (`Ash.Error.Framework`): System errors
- **Unknown** (`Ash.Error.Unknown`): Unexpected errors

Example error response:
```json
{
  "errors": [
    {
      "message": "Forbidden",
      "code": "forbidden",
      "fields": [],
      "short_message": "Authorization failed"
    }
  ]
}
```

## Testing the API

### Using GraphQL Playground

1. Start Phoenix server: `mix phx.server`
2. Navigate to: `http://localhost:4000/api/graphql`
3. Use the interactive playground to test queries and mutations

### Example Test Workflow

```graphql
# 1. Start a workflow
mutation {
  startWorkflow(input: {
    sourceDomain: THUNDERVINE
    rootEventName: "test.workflow.started"
    correlationId: "test-correlation-123"
  }) {
    result {
      id
      correlationId
      status
    }
  }
}

# 2. Create a workflow node
mutation {
  recordNodeStart(input: {
    workflowId: "<workflow-id-from-step-1>"
    nodeType: EVENT
    sourceName: "test.event"
    eventId: "<some-event-uuid>"
  }) {
    result {
      id
      status
    }
  }
}

# 3. Mark node as successful
mutation {
  markNodeSuccess(id: "<node-id-from-step-2>", completionPayload: {result: "success"}) {
    result {
      id
      status
      completedAt
    }
  }
}

# 4. Seal the workflow
mutation {
  sealWorkflow(id: "<workflow-id-from-step-1>") {
    result {
      id
      status
      sealedAt
    }
  }
}

# 5. Query the completed workflow
query {
  workflowByCorrelation(correlationId: "test-correlation-123") {
    id
    status
    sealedAt
  }
}
```

## Architecture Notes

### Domain-Level Configuration

All GraphQL queries and mutations are defined at the **domain level** (`Thunderline.Thundervine.Domain`), not at the resource level. This follows AshGraphql best practices and prevents duplicate type definitions.

### Resource-Level Configuration

Resources only define:
- GraphQL type name (e.g., `type :workflow`)
- Extensions marker (`AshGraphql.Resource`)

Resources do NOT define:
- Individual queries or mutations (domain handles this)
- Field policies (requires `public?: true` on attributes)

### Pattern Compliance

ThunderVine GraphQL implementation follows the same pattern as:
- `Thunderline.Thundergrid.Domain` (spatial operations)
- `Thunderline.Thunderlink.Domain` (communication)
- `Thunderline.Thunderbolt.Domain` (VIM operations)

## Future Enhancements

Potential GraphQL API extensions:

1. **Subscriptions**: Real-time workflow status updates
   ```graphql
   subscription {
     workflowStatusChanged(correlationId: "xyz") {
       id
       status
       sealedAt
     }
   }
   ```

2. **Batch Operations**: Bulk workflow operations
   ```graphql
   mutation {
     startWorkflows(inputs: [...]) {
       results {
         id
         correlationId
       }
     }
   }
   ```

3. **Advanced Filtering**: Complex workflow queries
   ```graphql
   query {
     workflows(filter: {
       status: SEALED
       sourceDomain: THUNDERVINE
       insertedAfter: "2025-01-01"
     }) {
       id
       correlationId
     }
   }
   ```

4. **Pagination**: Large result set handling
   ```graphql
   query {
     workflows(page: {limit: 20, offset: 0}) {
       pageInfo {
         hasNextPage
         totalCount
       }
       results {
         id
         correlationId
       }
     }
   }
   ```

5. **Field Policies**: Granular attribute access control (requires making attributes `public?: true`)

## Related Documentation

- [HC-29 Completion Report](HC-29_COMPLETION_REPORT.md) - ThunderVine domain implementation
- [ThunderVine Handbook](thunderline_handbook.md#thundervine) - Domain architecture
- [Ash GraphQL Guide](deps/ash_graphql/usage-rules.md) - Framework usage rules
- [AshAuthentication Guide](deps/ash_authentication/usage-rules.md) - Authorization patterns

## Troubleshooting

### Common Issues

**Issue**: "Type name is not unique" error during compilation
- **Cause**: GraphQL type names ending in `_edge` collide with Relay connection types
- **Solution**: Rename type to avoid `_edge` suffix (e.g., `workflow_link` instead of `workflow_edge`)

**Issue**: "Field reference(s) in field policy" error
- **Cause**: Field policies require attributes marked `public?: true`
- **Solution**: Use action-level policies instead of field policies, or mark attributes as public

**Issue**: "Authorization failed" errors in GraphQL responses
- **Cause**: Missing authentication token or insufficient permissions
- **Solution**: Include valid auth token in request headers and ensure actor has required role

**Issue**: "Resource is trying to define query/mutation which requires a GraphQL type"
- **Cause**: Missing `type :resource_name` in resource's `graphql do` block
- **Solution**: Add type definition to resource GraphQL configuration

## Changelog

### 2025-01-17 - Initial GraphQL API Implementation
- Added AshGraphql.Domain extension to ThunderVine.Domain
- Configured 11 queries (workflow, nodes, edges, snapshots)
- Configured 9 mutations (start, seal, update, record, mark, create, capture)
- Added comprehensive role-based policies (admin, system, authenticated)
- Added AshGraphql.Resource extension to all 4 resources
- Renamed WorkflowEdge GraphQL type to WorkflowLink (avoid Relay collision)
- Updated graphql_schema.ex to expose ThunderVine.Domain
