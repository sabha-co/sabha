# frozen_string_literal: true

# SaaS Engine Routes
#
# Routes for this engine are defined INLINE in lib/campfire/saas/engine.rb
# rather than in this file. This is intentional because:
#
# 1. Routes are PREPENDED to take precedence over core Campfire routes
# 2. Routes use CONSTRAINTS to only match when outside workspace context
# 3. Routes need access to ApplicationRecord.current_tenant which isn't
#    available during normal route loading
#
# The inline route definition in engine.rb uses:
#
#   app.routes.prepend do
#     constraints(->(req) { ApplicationRecord.current_tenant.blank? }) do
#       # SaaS routes (landing, sessions, workspaces, etc.)
#     end
#   end
#
# This ensures SaaS routes only match when no workspace is in the path,
# allowing requests like /1000001/rooms/general to fall through to
# core Campfire routes with the tenant context set.
#
# See: lib/campfire/saas/engine.rb for the actual route definitions.
