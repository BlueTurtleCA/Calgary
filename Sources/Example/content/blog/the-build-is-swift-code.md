---
date: 2026-01-12
title: The build is Swift code
description: Why Calgary's pipeline is code instead of a config file.
---

Most static site generators are driven by a config file: a list of plugins,
some frontmatter conventions, and a directory layout the generator guesses
at.

Calgary takes the opposite view. The build is an executable you write: a
`Site` configured with daisy-chained steps — copy assets, build CSS, render
pages, open the result. If a step is not in the pipeline, it does not
happen.
