# Branding Customization Guide

This guide explains how to fully customize Smallbets Community Edition to match your brand identity. All branding can be configured through environment variables and asset files—no code changes required!

## Table of Contents

- [Environment Variables](#environment-variables)
- [Visual Assets](#visual-assets)
- [Custom Styles](#custom-styles)
- [Advanced Customization](#advanced-customization)
- [Testing Your Branding](#testing-your-branding)

## Environment Variables

All textual branding is controlled through environment variables in your `.env` file.

### Application Identity

These variables define how your community is named and identified:

```bash
# The full name of your community
APP_NAME="My Awesome Community"

# Short name for mobile/PWA (keep under 12 characters)
APP_SHORT_NAME="MAC"

# Description shown in PWA manifest and meta tags
APP_DESCRIPTION="A welcoming community for creative entrepreneurs"

# Your primary domain (without https://)
APP_HOST="chat.yourdomain.com"
```

**Where these appear:**
- `APP_NAME`: Page titles, email subject lines, welcome messages, sign-in pages, PWA manifest
- `APP_SHORT_NAME`: Mobile home screen icon label
- `APP_DESCRIPTION`: PWA description, meta tags, app store descriptions
- `APP_HOST`: Email links, URL generation, CSP policies

### Contact & Support

Configure how your community communicates with members:

```bash
# Support email shown in error messages and help pages
SUPPORT_EMAIL="support@yourdomain.com"

# Name shown in "From" field of emails
MAILER_FROM_NAME="My Awesome Community"

# Email address shown in "From" field
MAILER_FROM_EMAIL="noreply@yourdomain.com"
```

**Where these appear:**
- `SUPPORT_EMAIL`: Error messages, help contact buttons, footer
- `MAILER_FROM_NAME` & `MAILER_FROM_EMAIL`: All outgoing emails (sign-in codes, notifications, etc.)

### Visual Branding

Control the colors used in your PWA (Progressive Web App):

```bash
# Primary theme color (hex code)
THEME_COLOR="#1d4ed8"

# Background color (hex code)
BACKGROUND_COLOR="#ffffff"
```

**Where these appear:**
- `THEME_COLOR`: Mobile browser address bar, PWA theme
- `BACKGROUND_COLOR`: PWA splash screen background

**Color recommendations:**
- Use your brand's primary color for `THEME_COLOR`
- Use white (#ffffff) or your brand's background color for `BACKGROUND_COLOR`
- Ensure good contrast between the two

### Analytics (Optional)

If you use Plausible Analytics:

```bash
# Your Plausible analytics domain
ANALYTICS_DOMAIN="yourdomain.com"
```

Leave empty to disable analytics tracking.

### Security

Configure Content Security Policy frame ancestors:

```bash
# Comma-separated list of allowed domains for iframe embedding
CSP_FRAME_ANCESTORS="https://yourdomain.com, https://*.yourdomain.com"
```

**Default behavior:**
If not set, automatically uses your `APP_HOST` value.

## Visual Assets

Replace these image files with your own branding:

### Favicons & Icons

Located in `app/assets/images/icons/`:

| File | Size | Purpose |
|------|------|---------|
| `favicon.ico` | 16x16 | Browser tab icon (ICO format) |
| `favicon-16x16.png` | 16x16 | Small browser icon |
| `favicon-32x32.png` | 32x32 | Standard browser icon |
| `apple-touch-icon.png` | 180x180 | iOS home screen icon |
| `android-chrome-192x192.png` | 192x192 | Android home screen icon |
| `android-chrome-512x512.png` | 512x512 | Android splash screen |

### Logo Files

Located in `app/assets/images/logos/`:

| File | Size | Purpose |
|------|------|---------|
| `app-icon.png` | 512x512 | Primary app logo |
| `app-icon-192.png` | 192x192 | Smaller app logo variant |

### Default Icon

The `campfire-icon.png` in `app/assets/images/` is used as a fallback. Replace it with your brand's icon.

### Creating Your Icons

**Quick method using a single source image:**

1. Start with a high-resolution square logo (1024x1024px minimum)
2. Use an online tool like [RealFaviconGenerator](https://realfavicongenerator.net/)
3. Upload your logo and download the generated icon pack
4. Replace the files in the directories above

**Design tips:**
- Use simple, recognizable designs that work at small sizes
- Ensure good contrast against both light and dark backgrounds
- Test how your icon looks at 16x16px
- For iOS, consider providing extra padding (safe area)

## Custom Styles

Administrators can add custom CSS directly through the admin interface:

1. Log in as an administrator
2. Go to `/accounts/edit`
3. Scroll to "Custom Styles"
4. Add your CSS

**Example custom styles:**

```css
/* Change primary button colors */
.btn-primary {
  background-color: #your-brand-color;
  border-color: #your-brand-color;
}

/* Customize header */
#header {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
}

/* Custom fonts */
body {
  font-family: 'Your Custom Font', -apple-system, BlinkMacSystemFont, sans-serif;
}
```

**Note:** Custom styles are stored per account, not globally. Each community can have its own styles.

## Advanced Customization

### Logo Upload

Smallbets Community Edition supports custom logo uploads through the admin panel:

1. Go to `/accounts/edit` as administrator
2. Upload your logo in the "Account Logo" section
3. The logo will automatically replace default branding

### Modifying the BrandingConfig Service

For developers who want to add more branding options:

Edit `app/services/branding_config.rb`:

```ruby
class BrandingConfig
  class << self
    # Add your custom branding methods here
    def custom_footer_text
      ENV.fetch("CUSTOM_FOOTER_TEXT", "© 2024 Your Community")
    end

    def twitter_handle
      ENV.fetch("TWITTER_HANDLE", "@yourcommunity")
    end
  end
end
```

Then use throughout your views:

```erb
<%= BrandingConfig.custom_footer_text %>
<%= link_to "@#{BrandingConfig.twitter_handle}", "https://twitter.com/#{BrandingConfig.twitter_handle}" %>
```

### Translations & Internationalization

The app includes built-in translation support. To customize text:

1. Edit locale files in `config/locales/`
2. Add your translations for different languages
3. Community members can select their preferred language

## Testing Your Branding

### Local Testing

1. Set your environment variables in `.env`
2. Restart your Rails server: `bin/rails restart`
3. Visit `http://localhost:3000`
4. Test these pages:
   - `/` - Home/marketing page
   - `/sign_in` - Sign in page
   - `/accounts/edit` - Settings (as admin)
   - Check email templates by triggering sign-in codes

### PWA Testing

To test Progressive Web App branding:

1. Deploy to a production server (PWA requires HTTPS)
2. Visit on mobile browser
3. Check "Add to Home Screen" functionality
4. Verify:
   - Home screen icon looks correct
   - App name displays correctly
   - Splash screen uses your branding
   - Theme color appears in mobile browser

### Email Testing

Test email branding:

```bash
# In Rails console
rails console

# Send a test auth token email
user = User.first
auth_token = user.auth_tokens.create!(expires_at: 15.minutes.from_now)
auth_token.deliver_later
```

Check that emails show:
- Correct "From" name and email
- Your app name in subject line
- Your app name in email body
- Correct support email address

### Browser Testing Checklist

- [ ] Favicon appears in browser tabs
- [ ] Page titles show your app name
- [ ] Error messages use your support email
- [ ] Sign-in page shows your branding
- [ ] Welcome message uses your app name
- [ ] Help/support buttons link to your support email
- [ ] Footer shows your app name
- [ ] PWA install shows correct name and icon

## Troubleshooting

### Changes Not Appearing

**Problem:** Updated environment variables but changes don't show

**Solution:**
```bash
# Development: Restart Rails server
bin/rails restart

# Production with Docker: Restart containers
docker-compose restart

# Production with Kamal: Redeploy
kamal deploy
```

### Icons Not Updating

**Problem:** Replaced icon files but old icons still showing

**Solution:**
```bash
# Clear browser cache, or test in incognito mode
# For PWA: Uninstall the app and reinstall

# Force asset recompilation in production:
docker-compose exec app bin/rails assets:precompile
docker-compose restart
```

### Email "From" Name Not Changing

**Problem:** Emails still show old "From" name

**Solution:**

1. Check that `MAILER_FROM_NAME` and `MAILER_FROM_EMAIL` are set
2. Restart your application
3. Check `app/mailers/application_mailer.rb` is using `BrandingConfig`
4. For some email providers, you may need to verify the sender domain

### CSS Not Applying

**Problem:** Custom CSS in admin panel not showing

**Solution:**

1. Ensure you're logged in as administrator
2. CSS is account-specific; verify you're viewing the right account
3. Check browser console for CSS errors
4. CSS is loaded inline; it may be cached by the browser

## Examples

### Startup Community

```bash
APP_NAME="Startup Founders Club"
APP_SHORT_NAME="SFC"
APP_DESCRIPTION="A community for early-stage startup founders"
APP_HOST="chat.startupfounder.club"
SUPPORT_EMAIL="help@startupfounder.club"
THEME_COLOR="#10b981"  # Green
BACKGROUND_COLOR="#ffffff"
```

### Creative Community

```bash
APP_NAME="Creative Collective"
APP_SHORT_NAME="Creative"
APP_DESCRIPTION="Where artists and creators collaborate"
APP_HOST="community.creativecollective.io"
SUPPORT_EMAIL="support@creativecollective.io"
THEME_COLOR="#8b5cf6"  # Purple
BACKGROUND_COLOR="#faf5ff"  # Light purple
```

### Developer Community

```bash
APP_NAME="DevHub"
APP_SHORT_NAME="DevHub"
APP_DESCRIPTION="A community for developers to learn and grow"
APP_HOST="chat.devhub.community"
SUPPORT_EMAIL="hello@devhub.community"
THEME_COLOR="#0ea5e9"  # Blue
BACKGROUND_COLOR="#0f172a"  # Dark blue
```

## Best Practices

1. **Keep APP_NAME concise** - It appears in many places; shorter is better
2. **Use consistent branding** - Match your website colors and fonts
3. **Test on mobile** - Most users will access via mobile
4. **Verify emails** - Test email delivery with your branding before launch
5. **Use high-quality icons** - Low-quality icons reflect poorly on your brand
6. **Document custom changes** - If you modify code, document it for future reference
7. **Test dark mode** - Ensure your branding works in dark mode if users enable it

## Need Help?

- Check the [main README](README.md) for deployment help
- Review [campfire-mods.md](campfire-mods.md) for customization examples
- Original Small Bets repo: [antiwork/smallbets](https://github.com/antiwork/smallbets)
- Open an issue on GitHub if you encounter problems

---

**Remember:** The beauty of Smallbets Community Edition is that everything is customizable. Make it yours! 🎨
