---
template: home
variables:
  title: Blue Turtle Canada
---

Hi, welcome to {{ title }}!

This page was built by **Calgary**, a static site generator where the build
pipeline is Swift code. The header and footer are components — plain HTML
files that the template includes.

{% include "components/hero" %}

## How this page is built

- `content/index.md` is the page you are reading.
- `templates/home.html` is the template it renders into.
- `components/header.html` and `components/footer.html` are included by the template.
- `components/hero.md` is a markdown component that the page includes.
