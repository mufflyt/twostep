# Pre-correction artifacts — NOT for analysis

`age_matched_results_CONTAMINATED_2020.csv` is the 2020 age-matched result as it
stood at commit b5313c8, computed against an isochrone set that held 3,909
origins instead of 4,050. Forty-four physician locations had no catchment and the
runner was configured to DROP unmatched supply, so their supply silently
vanished: 12 of 14 cells lost origins, deflating access by up to 3.67%.

It is retained for ONE purpose: the appendix demonstrates the historical defect
and needs the contaminated numbers to do so. Fixing the live artifact underneath
that paragraph made it compute a 0.000% shortfall from 0 lost origins -- a
description of the defect written from data in which the defect had been
repaired.

Never read this file for any analytic purpose. The authoritative artifact is
artifacts/2sfca/agematched_panel/age_matched_panel.csv.
