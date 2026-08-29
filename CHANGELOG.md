# Changelog

**The changelog for this project is [`NEWS.md`](NEWS.md).**

R packages record their release history in `NEWS.md`: it is what
`utils::news()` parses, what `pkgdown` renders as the Changelog tab, and what
CRAN and `R CMD check` expect. This file exists because "CHANGELOG.md" is where
people coming from other ecosystems look first.

It deliberately does **not** restate the entries. A second hand-maintained copy
of the same history is a second thing to forget to update, and a changelog that
disagrees with itself is worse than one that lives in a single place — the same
reason this codebase refuses silently divergent scientific keys.

If you are looking for:

| you want | read |
|---|---|
| what changed, by version | [`NEWS.md`](NEWS.md) |
| how to cite this work | [`CITATION.cff`](CITATION.cff) / [`CITATION.bib`](CITATION.bib) |
| where every figure came from | [`docs/FIGURE_PROVENANCE.md`](docs/FIGURE_PROVENANCE.md) |
| where every data input came from | [`docs/DATA_PROVENANCE.md`](docs/DATA_PROVENANCE.md) |
| which isochrone set the analysis used, and why it is pinned by hash | [`docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md`](docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md) |
| whether this commit is publishable | `bash tools/ci/release_audit.sh` |
| where the canonical copies of the large inputs live | [`docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md`](docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md) §6 |
| what the method does and why | `vignette("e2sfca-accessibility")` |
