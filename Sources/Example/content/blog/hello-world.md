---
date: 2026-01-05
title: Hello, world
description: The first post on the Blue Turtle Canada blog.
---

This is the first post on the blog. It is a markdown page in `content/blog/`,
and it does not declare a `template` of its own: the `blog` collection in
`Main.swift` gives it the `post` template.

Its `title` and `description` are ordinary frontmatter keys — any key in a
page's frontmatter is a variable, so the blog index can show a post's
description without any extra plumbing.
