# Security

## Supported versions

Only the latest version on the `main` branch receives fixes.

## Reporting a vulnerability

Please don't open a public issue. Use [GitHub's private reporting](../../security/advisories/new) (Security tab ▸ Report a vulnerability): only the maintainer can see it.

Describe the problem, how to reproduce it and what it allows. You'll get a reply within two weeks.

## What matters most

FotoTag runs locally and writes to your photo files, so the main concerns are:
- writes outside the folders the user has authorized;
- loss or damage of photos, RAW files or `.xmp` sidecars;
- data sent over the network beyond downloading models from Hugging Face;
- model files or JSON profiles crafted to run code.
