# Sabha Positioning

Three products, one codebase. This document captures how Sabha looks from each audience so we can write docs, design marketing pages, and make product decisions with a clear picture.

---

## What is Sabha?

Sabha is a community chat platform built on [Campfire](https://once.com/campfire) by 37signals. It gives communities a simple, intentional space to talk — rooms for topics, threads for depth, DMs for private conversations, and full-text search across everything.

It is not a Discord clone. No voice channels, no bots marketplace, no server discovery. It is not an enterprise tool. No compliance dashboards, no audit logs, no SAML. Sabha is text-first chat that does fewer things than Slack or Discord, on purpose. Every feature that exists works well. That's the trade.

The core values across every version of Sabha:

- **Simplicity over features.** Rooms, threads, DMs, search. That's the product.
- **Ownership.** Self-hosters own their server. Cloud customers own their dedicated instance. SaaS users own their data (exportable, open source). Nobody is trapped.
- **No noise.** Activity feed instead of a wall of unread channels. Threads by default. Push notifications that actually matter. No typing indicators, no presence pressure, no algorithmic highlights.
- **Built on proven foundations.** Campfire by 37signals isn't a weekend project. Sabha extends it, not replaces it. Battle-tested Rails, Hotwire for real-time, SQLite in production.

Sabha ships as three products — self-hosted (free, your server), Sabha Cloud (managed, we run it), and sabha.co (hosted SaaS). Same app, different wrappers. The difference is who handles the infrastructure.

---

## For the developer: self-hosted Sabha

**Who they are:** An open source maintainer, a project lead, or a small dev team. They run a GitHub repo (or a few) and need a place for their community to talk that isn't GitHub Issues and isn't Discord.

**The problem they have:** Discord is where open source communities go to die. Conversations vanish into an unindexed void. Slack is expensive and locks you in. GitHub Discussions is fine for async Q&A but terrible for real-time conversation. They want something they control.

**What Sabha is to them:** A chat app they deploy on their own server, point their domain at, and invite their community to. It's built on Campfire by 37signals — battle-tested Rails, SQLite in production, zero external dependencies beyond a single server. They own every byte of data.

**Why they'd pick Sabha over the alternatives:**

- **Not Discord.** Messages are searchable. Threads keep conversations organized. No algorithmic nonsense, no Nitro upsells, no "boosting." Just chat.
- **Not Slack.** No per-seat pricing. No 90-day message limits on free plans. Deploy it and it's yours forever.
- **Not Zulip/Mattermost/Rocket.Chat.** Those are enterprise tools cosplaying as community platforms. Sabha is opinionated and lightweight — a Rails app, not a Kubernetes deployment.
- **Self-hostable, actually.** One server, SQLite, no Redis required for basic usage. `docker compose up` and you're running. No managed database, no object storage, no twelve environment variables to configure.

**What they care about:**

- Easy deployment (Docker, bare metal, whatever they already run)
- Custom branding (their project's name, logo, colors — not Sabha's)
- Low maintenance (SQLite means no database server to babysit)
- Import from Slack (migrating an existing community)
- Open source (they can read the code, fix bugs, contribute back)

**What they don't care about:**

- Multi-tenancy, workspace management, billing
- Managed hosting or SLAs
- Enterprise features like SSO/SAML

**How we talk to them:** Like a developer talking to another developer. Show the architecture, link to the repo, explain the deployment. The README is the marketing page. They'll judge the project by the code quality, the commit history, and whether `bin/setup` actually works.

---

## For the community builder: sabha.co

**Who they are:** Someone building a community — a course creator, a newsletter author, a hobbyist group organizer, a startup founder who wants a private space for their users. They're not technical (or they are, but don't want to manage infrastructure).

**The problem they have:** They've outgrown group chats. WhatsApp and Telegram are chaotic. Discord is powerful but overwhelming — too many bots, too many permissions, too much configuration. Slack is for work, not community. They want something simple that feels intentional.

**What Sabha is to them:** A hosted chat platform at sabha.co where they create a workspace, invite their people, and start talking. No servers to manage, no Docker, no SSH. Sign up, name your workspace, share the invite link.

**Why they'd pick Sabha over the alternatives:**

- **Simpler than Discord.** No server templates, no role hierarchies, no bot marketplace. Rooms, threads, DMs, search. That's it. People show up and start talking.
- **More focused than Slack.** Activity feed instead of a wall of unread channels. Threads by default. Push notifications that actually matter.
- **Feels like yours.** Custom name, logo, and theme color. Your community, your brand — not "a Discord server" or "a Slack workspace."
- **Respects attention.** No typing indicators blinking constantly, no presence pressure, no algorithmic "highlights." Async-friendly with real-time when you need it.
- **Open source backing.** Even on the hosted version, the code is open. No vendor lock-in — if sabha.co ever disappears, export your data and self-host.

**What they care about:**

- Dead-simple onboarding (email sign-up, magic link auth, no passwords)
- Invite links that just work
- Mobile-friendly (PWA, push notifications)
- Clean UI that doesn't need a tutorial
- File sharing (images, PDFs, videos inline)
- Making their community feel like *theirs*, not a generic chat app

**What they don't care about:**

- The tech stack, deployment architecture, or database choices
- Git, Docker, or command lines
- Self-hosting (that's what sabha.co is for)

**How we talk to them:** Like a product, not a project. Show the UI, emphasize the feeling. "Create your community in 30 seconds." Screenshots, not architecture diagrams. The landing page is the marketing page. They'll judge Sabha by whether it looks good and whether their first message sends without friction.

---

## For the team that wants it handled: cloud.sabha.co

**Who they are:** A non-technical team, a growing community, or a developer who simply doesn't want to deal with ops. They want their own Sabha instance — dedicated server, custom domain, full control — but they don't want to SSH into anything or think about Docker.

**The problem they have:** Self-hosting is appealing in theory. In practice, it means provisioning a server, configuring DNS, setting up SSL, managing backups, and keeping the thing updated. They'd rather pay someone to handle all of that and just use the product.

**What Sabha Cloud is to them:** A one-click deployment platform at cloud.sabha.co. They pick a subdomain (e.g., `acme.cloud.sabha.co`), click deploy, and get a fully running Sabha instance on a dedicated server in about 5 minutes. Automated backups, managed SSL, health monitoring — all included.

**How it differs from sabha.co (SaaS):**

- **Dedicated server.** Each Sabha Cloud customer gets their own DigitalOcean droplet. Not a shared multi-tenant database — their own isolated server with their own SQLite database.
- **Full Sabha.** No workspace limits, no storage caps, no feature restrictions. It's the complete self-hosted experience without the self-hosting.
- **Custom domain support.** Bring your own domain (planned), or use a `*.cloud.sabha.co` subdomain.
- **Data portability.** The server is running standard Sabha. If they ever want to leave, they can take over the server or export everything.

**Why they'd pick Sabha Cloud over self-hosting:**

- **Zero ops.** No Docker, no DNS records, no SSL certificates, no server maintenance. Click a button.
- **Automatic backups.** Continuous SQLite replication to Cloudflare R2 via Litestream. Their data is safe without them thinking about it.
- **Managed updates.** When Sabha releases a new version, one-click update (bulk redeploy for the platform admin).
- **Health monitoring.** Automated uptime checks every 5 minutes. If something breaks, we know before they do.

**Why they'd pick Sabha Cloud over sabha.co (SaaS):**

- **Isolation.** Their data lives on a dedicated server, not shared infrastructure. Better for privacy-sensitive teams.
- **No limits.** No per-workspace storage caps or member limits. The server is theirs.
- **Custom domain.** Their community lives at their URL, not a sabha.co path.

**What they care about:**

- One-click setup (sign up, pick a name, deploy)
- Automatic backups they don't have to think about
- Uptime and reliability
- A clean dashboard to manage their server
- Knowing they can leave anytime (no lock-in)

**What they don't care about:**

- The tech stack (DigitalOcean, Litestream, Caddy — they don't need to know)
- Server administration, SSH, or Docker
- The open source repo (though they appreciate that it exists)

**How we talk to them:** Like a hosting service that respects their intelligence. Not "enterprise cloud platform" — more like "we'll run Sabha for you." Show the deployment flow, the dashboard, the backup status. They want to know it works and that someone competent is behind it.

---

## The three products at a glance

|                    | Self-Hosted              | Sabha Cloud (cloud.sabha.co)     | Sabha SaaS (sabha.co)          |
|--------------------|--------------------------|----------------------------------|--------------------------------|
| **Price**          | Free (your server costs) | Monthly subscription             | Free                           |
| **Setup**          | Manual (DNS, SSL, server)| One-click (~5 min)               | Instant (sign up & go)         |
| **Infrastructure** | You manage everything    | Dedicated server, we manage it   | Shared multi-tenant platform   |
| **Stack**          | Kamal Proxy + ActionCable| Caddy + AnyCable-Go              | Kamal Proxy + AnyCable-Go      |
| **Database**       | Single SQLite            | SQLite + backup to R2            | SQLite/tenant + PostgreSQL     |
| **Backups**        | Manual (you manage)      | Auto (Litestream to R2)          | Platform-managed               |
| **Custom domain**  | Yes (you configure it)   | Included (planned)               | No                             |
| **Limitations**    | Your time & skills       | No limits on scale or features   | Per-workspace storage/members  |
| **Best for**       | Technical teams wanting max control | Non-technical teams wanting chat, not ops | Small teams & communities |

**Same app, different wrappers.** The Sabha application is identical across all three. The difference is who handles the infrastructure and what trade-offs come with that.

---

## The overlap

All three audiences share the same core values:

- **Simplicity over features.** Sabha does fewer things than Slack or Discord, on purpose.
- **Ownership.** Self-hosters own their server. Cloud customers own their dedicated instance. SaaS users own their data (exportable, open source). Nobody is trapped.
- **No noise.** Threads, activity feed, and granular notifications exist to keep the signal-to-noise ratio high.
- **Built on proven foundations.** Campfire by 37signals isn't a weekend project. Sabha extends it, not replaces it.

The product is the same. The framing is different. One audience reads the README. Another reads the Cloud landing page. The third reads the SaaS landing page. All three should feel like Sabha was built for them.

---

## What Sabha is not

- **Not an enterprise tool.** No compliance dashboards, no audit logs, no SAML. If you need those, you need something else.
- **Not a Discord clone.** No voice channels, no bots marketplace, no server discovery. Sabha is text-first.
- **Not trying to be everything.** The feature list is short on purpose. Every feature that exists works well. That's the trade.
