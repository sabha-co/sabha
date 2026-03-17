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

### Favicons & Icons

Replace files in `app/assets/images/icons/`:

| File | Size | Purpose |
|------|------|---------|
| `favicon.ico` | 16x16 | Browser tab icon (ICO format) |
| `favicon-16x16.png` | 16x16 | Small browser icon |
| `favicon-32x32.png` | 32x32 | Standard browser icon |
| `apple-touch-icon.png` | 180x180 | iOS home screen icon |
| `android-chrome-192x192.png` | 192x192 | Android home screen icon |
| `android-chrome-512x512.png` | 512x512 | Android splash screen |

### Logo Files

Replace files in `app/assets/images/logos/`:

| File | Size | Purpose |
|------|------|---------|
| `app-icon.png` | 512x512 | Primary app logo |
| `app-icon-192.png` | 192x192 | Smaller app logo variant |

These are also the fallback when no custom logo is uploaded via the admin panel (see below).

**Quick method:** Start with a 1024x1024px square logo, run it through [RealFaviconGenerator](https://realfavicongenerator.net/), and drop the generated files into the directories above.

### Logo Upload

Administrators can upload a custom logo at `/accounts/edit` — it replaces the default `app-icon` files in the UI.

## Custom Styles

Administrators can add custom CSS through the admin interface at `/accounts/custom_styles/edit`.

Sabha uses CSS custom properties for theming. Override them to match your brand:

```css
:root {
  --color-text: #1a1a1a;
  --color-primary: #2563eb;
  --color-link: #2563eb;
  --color-border: #e5e7eb;
}
```

See `app/javascript/entrypoints/application.css` for the full list of available properties.

Custom styles are stored per account and loaded inline.

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
