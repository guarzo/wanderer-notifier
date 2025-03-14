# Templates Directory

This directory contains HTML templates used by the Wanderer Notifier application.

## Files

- `dashboard.html.eex` - The main dashboard template for the web interface

## Notes for Development

During development, templates are loaded from `lib/wanderer_notifier/web/templates/`.
For production releases, templates are copied to this directory (`priv/templates/`) during the build process.

If you add new templates, make sure to:

1. Place the original template in `lib/wanderer_notifier/web/templates/`
2. Ensure the build process copies it to `priv/templates/` (this is handled by the build script)

The application will first try to load templates from the `priv` directory, and fall back to the `lib` directory if needed. 