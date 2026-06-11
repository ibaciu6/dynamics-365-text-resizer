# Dynamics 365 Text Resizer

A Chrome and Firefox extension that makes text fields in Dynamics 365 vertically resizable and auto-fits them to their content.

**[Install on Firefox](https://addons.mozilla.org/en-US/firefox/addon/dynamics-365-text-resizer/)** · **[Install on Chrome](https://chrome.google.com/webstore/detail/chhnlfklbbdncogckpoeejhpmbanfbpp)** · **[Privacy Policy](https://ibaciu6.github.io/dynamics-365-text-resizer/privacy-policy.html)**

## Features

- Auto-fits Description, Notes, and Resolution fields to their content
- Vertical resize handle on all text fields
- Supports plain `<textarea>` elements and Quill rich-text editors
- Configurable minimum height (slider in popup)
- Add custom field labels via the popup
- Hover highlight for enhanced fields
- "Format" button to strip markdown formatting

## Supported Dynamics 365 regions

All public cloud regions (`*.crm.dynamics.com`, `*.crm2–17.dynamics.com`, `*.microsoftdynamics.us`, `*.microsoftdynamics.de`).

## Folder structure

```
chrome/    MV3 source for Chrome Web Store
firefox/   MV2 source for Firefox Add-ons (AMO)
docs/      GitHub Pages site (privacy policy, landing page)
```

Only two files differ between platforms (`manifest.json`, `background.js`). All other source files are identical.

## Privacy

This extension collects no user data whatsoever. See [Privacy Policy](https://ibaciu6.github.io/dynamics-365-text-resizer/privacy-policy.html).

## License

MIT
