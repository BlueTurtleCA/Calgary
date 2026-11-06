---
date: 2026-01-19
title: Pagination
description: How the blog index splits its posts across pages.
---

The blog collection in `Main.swift` declares `paginate: 2`, so the index
splits its posts across pages: the two newest on `/blog/`, the rest under
`/blog/page/2/`.

The index template renders once per page with `items` (the posts on this
page), `total`, `count`, `number`, `pageCount`, and `hasPrevious`/`hasNext`
variables, so the pagination links are just conditionals.
