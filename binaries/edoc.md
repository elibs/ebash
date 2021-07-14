# Binary edoc


edoc is used to automatically generate markdown documentation from the source code docstrings through the `opt_usage`
and `opt_parse` mechanisms. It also takes care of creating various index.md files to stitch all the documents together
in a more easily to navigate fashion. And finally it provides the ability to publish the generated documentation to
GitHub pages.

```Groff
OPTIONS
(*) Denotes required options
(&) Denotes options which can be given multiple times

   --publish
         Optionally publish the generated documents to GitHub Pages.

```
