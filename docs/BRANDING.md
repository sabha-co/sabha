# Branding Customization Guide

This guide explains how to customize Sabha's branding for a self-hosted deployment. All branding is configured through environment variables and asset files.

## Environment Variables

Set these in your `.env` file.

### Application Identity

```bash
# The name of your community — appears in page titles, emails, sign-in pages, PWA manifest
APP_NAME="My Awesome Community"

# Short name for mobile/PWA home screen icon (keep under 12 characters)
APP_SHORT_NAME="MAC"

# Description for PWA manifest and meta tags
APP_DESCRIPTION="A welcoming community for creative entrepreneurs"

# Your primary domain (without https://)
APP_HOST="chat.yourdomain.com"
```

### Contact & Support

```bash
# Shown in error messages and help pages
SUPPORT_EMAIL="support@yourdomain.com"

# "From" field in outgoing emails (sign-in codes, notifications, etc.)
MAILER_FROM_NAME="My Awesome Community"
MAILER_FROM_EMAIL="noreply@yourdomain.com"
```

### PWA Theme Colors

These control the mobile browser chrome and splash screen, not the app UI.

```bash
# Mobile browser address bar and PWA theme (default: #1d4ed8)
THEME_COLOR="#1d4ed8"

# PWA splash screen background (default: #ffffff)
BACKGROUND_COLOR="#ffffff"
```

Use your brand's primary color for `THEME_COLOR`. Ensure good contrast between the two.

### Analytics (Optional)

If you use [Umami Analytics](https://umami.is):

```bash
UMAMI_WEBSITE_ID="your-website-id"
# Self-hosted Umami instance (default: cloud.umami.is)
# UMAMI_HOST="your-umami-host.com"
```

Leave `UMAMI_WEBSITE_ID` unset to disable analytics.

### Content Security Policy

```bash
# Comma-separated list of allowed domains for iframe embedding
# Defaults to https://APP_HOST, https://*.APP_HOST
CSP_FRAME_ANCESTORS="https://yourdomain.com, https://*.yourdomain.com"
```

## Visual Assets

Sabha resolves icons from a small set of specific files. Replacing the files below is what actually changes what users see — other image files in the repo are not wired to the favicon or app icons.

### Browser favicon (SVG)

Modern browsers prefer the SVG favicon. Replace:

| File | Purpose |
|------|---------|
| `public/icon.svg` | Browser tab favicon (modern browsers) |

### App icon (PNG fallback, Apple touch icon, PWA)

These cover browsers without SVG support, the iOS home-screen icon, and the installable PWA. Replace both:

| File | Size | Purpose |
|------|------|---------|
| `app/assets/images/logos/app-icon.png` | 512x512 | PNG favicon fallback, `apple-touch-icon`, PWA icon |
| `app/assets/images/logos/app-icon-192.png` | 192x192 | Smaller PWA icon |

These are also the default when no custom logo is uploaded via the admin panel (see Logo Upload below).

### Social / link previews (Open Graph)

Shown when your URL is shared on social media or chat apps. Replace:

| File | Recommended | Purpose |
|------|-------------|---------|
| `public/sabha-og.jpg` | 1200x630 | `og:image` preview card |
| `public/icon.png` | 512x512 | `og:logo` |

Files in `public/` are served directly and need no recompilation. After replacing files under `app/assets/`, recompile assets in production (see [Icons Not Updating](#icons-not-updating)).

### Logo Upload

Administrators can upload a custom logo at `/accounts/edit`. It overrides the `app-icon` PNGs for the in-app logo, the PNG favicon, the Apple touch icon, and the PWA icons — without redeploying. It does **not** change the SVG favicon (`public/icon.svg`) or the Open Graph images, so replace those files directly if you need them branded.

## Example Configuration

```bash
APP_NAME="Startup Founders Club"
APP_SHORT_NAME="SFC"
APP_DESCRIPTION="A community for early-stage startup founders"
APP_HOST="chat.startupfounder.club"
SUPPORT_EMAIL="help@startupfounder.club"
MAILER_FROM_NAME="Startup Founders Club"
MAILER_FROM_EMAIL="noreply@startupfounder.club"
THEME_COLOR="#10b981"
BACKGROUND_COLOR="#ffffff"
```

## Troubleshooting

### Changes Not Appearing

Restart your server after changing environment variables:

```bash
# Development
bin/rails restart

# Production (Docker Compose)
docker compose restart
```

### Icons Not Updating

Clear your browser cache or test in incognito mode. For PWA, uninstall and reinstall the app.

In production, force asset recompilation:

```bash
docker compose exec app bin/rails assets:precompile
docker compose restart
```

### Email "From" Name Not Changing

1. Verify `MAILER_FROM_NAME` and `MAILER_FROM_EMAIL` are set
2. Restart the application
3. Some email providers require sender domain verification

## Need Help?

- See [DEPLOYMENT.md](./DEPLOYMENT.md) for deployment help
- Open an issue on [GitHub](https://github.com/sabha-co/sabha/issues)
