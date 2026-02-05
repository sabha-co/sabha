# Product PRD: Campfire Multi-Tenant SaaS

## Problem Statement

Campfire-CE is a self-hosted chat application. Currently, each deployment serves a single organization. Users who want to host chat for multiple organizations must deploy and maintain separate instances.

**Pain points:**
- Operators managing multiple communities need separate deployments
- Each deployment requires its own server, domain, and maintenance
- No way to offer "Campfire as a Service" to multiple customers
- Users belonging to multiple communities need separate accounts per instance

## Product Vision

Enable Campfire-CE to serve multiple isolated workspaces from a single deployment, allowing:
1. **Operators** to host multiple communities/organizations efficiently
2. **Users** to access all their workspaces with a single login
3. **Self-hosters** to continue using Campfire without any changes

## Target Users

### Persona 1: SaaS Operator
> "I want to run a chat service for multiple clients without managing separate servers."

- Hosts Campfire for multiple organizations
- Needs tenant isolation for security and privacy
- Wants centralized billing and administration
- Example: Agency hosting chat for multiple client companies

### Persona 2: Community Builder
> "I want to run multiple themed communities under one roof."

- Runs several related but separate communities
- Wants users to easily switch between communities
- Needs separate moderation per community
- Example: Creator with communities for different courses/products

### Persona 3: Multi-Workspace User
> "I'm a member of several Campfire workspaces and want one login for all."

- Belongs to multiple organizations using the same Campfire instance
- Wants seamless switching between workspaces
- Expects single sign-on experience (one email, one login)
- Example: Consultant working with multiple client workspaces

### Persona 4: Self-Hoster (unchanged)
> "I just want to run Campfire for my team. Keep it simple."

- Deploys Campfire for a single organization
- Doesn't need multi-tenancy features
- Wants zero additional complexity
- Example: Startup running internal team chat

## User Stories

### Authentication & Identity

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| U1 | New user | Sign up with just my email | I don't need to remember a password |
| U2 | Existing user | Log in with an auth code | I can securely access my account |
| U3 | Multi-workspace user | See all my workspaces after login | I can choose where to go |
| U4 | User | Switch workspaces without re-authenticating | Moving between workspaces is seamless |

### Workspace Management

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| W1 | New user | Create a new workspace | I can start my community |
| W2 | Workspace admin | Invite people via a shareable link | New members can easily join |
| W3 | Workspace admin | See and manage all members | I can control who has access |
| W4 | User | Join a workspace via invite code | I can access workspaces I'm invited to |
| W5 | User | Leave a workspace | I can remove myself from communities I no longer need |

### Workspace Experience

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| E1 | User | Have a separate profile per workspace | I can have different names/avatars in different contexts |
| E2 | User | Have my messages stay in the workspace | My data doesn't leak to other workspaces |
| E3 | Workspace admin | Configure workspace settings independently | Each workspace can have its own rules |
| E4 | User | Get notifications scoped to each workspace | I'm not overwhelmed by cross-workspace noise |

### Self-Hosted (Unchanged)

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| S1 | Self-hoster | Deploy without multi-tenancy | I get a simple, focused chat app |
| S2 | Self-hoster | Use password authentication | I can use traditional login if preferred |
| S3 | Self-hoster | Not see workspace switchers | The UI matches my single-org use case |

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Self-hosted deploys unaffected | 0 breaking changes | Existing deployments work without modification |
| Workspace creation success rate | >95% | New workspace setup completes without error |
| Cross-workspace login success | >99% | Users can switch workspaces without re-auth |
| Data isolation | 100% | No cross-workspace data leakage in security audit |
| Page load time (workspace switch) | <500ms | Time from click to workspace load |

## Scope

### In Scope (MVP)

- [ ] Single sign-on across workspaces (auth code / OTP)
- [ ] Workspace creation flow
- [ ] Workspace selector (post-login)
- [ ] Join workspace via invite code
- [ ] Separate user profiles per workspace
- [ ] Complete data isolation between workspaces
- [ ] Self-hosted mode unchanged (no multi-tenancy)

### In Scope (v1)

- [ ] Workspace settings management
- [ ] Member management (invite, remove, roles)
- [ ] Workspace-scoped notifications
- [ ] Admin dashboard for operators

### Out of Scope (v2 / Future)

- [ ] Billing and subscriptions
- [ ] Usage limits per workspace
- [ ] Custom domains per workspace
- [ ] Workspace templates
- [ ] Data export per workspace
- [ ] SSO/SAML integration

### Explicitly Out of Scope

- Cross-workspace messaging
- Shared rooms between workspaces
- Global user directory
- Workspace merging

## Feature Requirements

### FR1: Auth Code Authentication (OTP)

**What:** Users authenticate via email-based one-time codes instead of passwords.

**Requirements:**
- 6-character alphanumeric code
- 15-minute expiration
- Typo-tolerant (0/O, 1/I/L treated as same)
- Rate limited (10 attempts per 3 minutes)

**User flow:**
1. Enter email
2. Receive code via email
3. Enter code
4. Authenticated

### FR2: Workspace Selector

**What:** After authentication, users see their workspaces and can choose one.

**Requirements:**
- Show all workspaces user belongs to
- Display workspace name and user's role
- Option to create new workspace
- Option to join workspace via code
- Remember last visited workspace (optional)

### FR3: Workspace Creation

**What:** Users can create new workspaces.

**Requirements:**
- Provide workspace name
- Creator becomes administrator
- Generate unique workspace URL path
- Auto-create invite code
- Initialize with default settings

### FR4: Workspace Joining

**What:** Users can join existing workspaces via invite.

**Requirements:**
- Accept invite code (format: XXXX-XXXX-XXXX)
- Create membership for user in workspace
- Redirect to workspace after joining
- Support usage limits on invite codes

### FR5: Data Isolation

**What:** Each workspace's data is completely separate.

**Requirements:**
- Users cannot see other workspaces' rooms/messages
- File uploads scoped to workspace
- Search results limited to current workspace
- Real-time updates only from current workspace
- Background jobs execute in correct workspace context

### FR6: Self-Hosted Compatibility

**What:** Single-tenant deployments work without changes.

**Requirements:**
- Default deployment has no multi-tenancy
- No additional configuration required
- No performance overhead
- Existing features work identically
- Upgrade path doesn't break existing data

## Non-Functional Requirements

| Requirement | Specification |
|-------------|---------------|
| **Security** | Complete tenant isolation; no cross-workspace data access |
| **Performance** | Workspace switch <500ms; no degradation for self-hosted |
| **Scalability** | Support 1000+ workspaces per deployment |
| **Availability** | One workspace's issues don't affect others |
| **Backup** | Per-workspace backup and restore capability |
| **Compliance** | Data residency per workspace (future consideration) |

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Data leakage between workspaces | Critical | Low | Database-per-workspace architecture; security audit |
| Self-hosted breakage | High | Medium | Extensive testing; feature flagged rollout |
| Performance degradation | Medium | Medium | Connection pooling; lazy loading |
| Complex user mental model | Medium | Low | Clear UI; workspace context always visible |
| Migration complexity | Medium | Medium | Detailed upgrade guide; automated migration scripts |

## Dependencies

| Dependency | Type | Status |
|------------|------|--------|
| `activerecord-tenanted` gem | External | Available (Basecamp) |
| SQLite per-tenant support | Technical | Supported by gem |
| Path-based routing | Technical | Standard Rails |
| Email delivery (auth codes) | Infrastructure | Existing (Resend) |

## Timeline & Phases

### Phase 1: Foundation (MVP)
- Core infrastructure (database-per-workspace)
- Authentication (GlobalIdentity, auth codes)
- Workspace creation and joining
- Basic workspace selector

### Phase 2: Polish (v1)
- Member management
- Workspace settings
- Admin dashboard
- Notification scoping

### Phase 3: Monetization (v2)
- Billing integration
- Usage limits
- Advanced admin features

---

## Appendix: Glossary

| Term | Definition |
|------|------------|
| **Workspace** | An isolated tenant/organization within the multi-tenant deployment |
| **GlobalIdentity** | A user's cross-workspace identity (email-based) |
| **User** | A user's presence within a specific workspace (profile, role) |
| **Self-hosted** | Single-tenant deployment for one organization |
| **SaaS mode** | Multi-tenant deployment serving multiple workspaces |
| **Auth code (OTP)** | Email-based one-time code for passwordless authentication |

---

## Related Documents

- [Technical PRD](./multi-tenancy-technical-prd.md) - Architecture and implementation details
- [Implementation Tasks](./multi-tenancy-plans-and-tasks.md) - Development task breakdown
- [User Flows](./multi-tenant-user-flows.md) - Detailed user journey diagrams
