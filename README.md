# Dynamics 365 Text Resizer

A Chrome, Edge, and Firefox extension that makes text fields in Dynamics 365 vertically resizable and auto-fits them to their content.

**[Install on Firefox](https://addons.mozilla.org/en-US/firefox/addon/dynamics-365-text-resizer/)** · **[Install on Chrome](https://chrome.google.com/webstore/detail/chhnlfklbbdncogckpoeejhpmbanfbpp)** · **[Install on Edge](https://microsoftedge.microsoft.com/addons/detail/dynamics-365-text-resizer)** · **[Privacy Policy](https://ibaciu6.github.io/dynamics-365-text-resizer/privacy-policy.html)**

> The Edge listing is pending review. Edge uses the same Chromium Manifest V3 package as Chrome, so until it is live you can load the Chrome build via `edge://extensions` (Developer mode &rarr; Load unpacked).

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
chrome/    MV3 source for Chrome Web Store (also used as-is for Microsoft Edge Add-ons)
firefox/   MV2 source for Firefox Add-ons (AMO)
docs/      GitHub Pages site (privacy policy, landing page)
```

Edge is Chromium-based and accepts the Chrome Manifest V3 package unchanged, so it has no separate source folder — the Chrome build is submitted to the Edge Add-ons store directly. Only two files differ between the Chrome/Edge and Firefox builds (`manifest.json`, `background.js`); all other source files are identical.

## Privacy

This extension collects no user data whatsoever. See [Privacy Policy](https://ibaciu6.github.io/dynamics-365-text-resizer/privacy-policy.html).

## License

MIT
