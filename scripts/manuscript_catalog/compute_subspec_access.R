#!/usr/bin/env Rscript
source("R/contour_bands.R")      # SSOT: PRIMARY_ACCESS_BAND_SEC (60-min band)
source("R/access_categories.R")  # SSOT: DENOMINATOR_CATEGORY (total-female denom)
# PRIMARY ESTIMAND: subspecialty-specific geographic access.
# For each of the 7 subspecialties separately: % of U.S. women (total_female)
# within each drive-time threshold, per year. This is a per-discipline quantity
# (subspecialists serve DIFFERENT populations and are never pooled). The mean
# across the seven is a clearly-labeled SECONDARY summary only.
suppressWarnings(suppressMessages(library(dplyr)))
acc <- read.csv("scratchpad/manuscript_stage/ac587845_full/step_4_access_by_group.csv",
                stringsAsFactors = FALSE)
bands <- c(`30`=1800, `60`=3600, `120`=7200, `180`=10800)
by <- min(acc$year); ly <- max(acc$year)

tf <- acc %>% filter(category == DENOMINATOR_CATEGORY)
# per (subspecialty, band, year): percent already computed in the data
subspec <- sort(unique(tf$subspecialty))

# 2023 access matrix (subspec x band) + baseline + trend slope over all years
grid <- expand.grid(subspecialty = subspec, band_min = as.integer(names(bands)),
                    stringsAsFactors = FALSE)
res <- grid %>% rowwise() %>% mutate(
  rg = bands[[as.character(band_min)]],
  access_2023 = { s<-tf %>% filter(subspecialty==subspecialty, range==rg, year==ly); s$percent[1] },
  access_2013 = { s<-tf %>% filter(subspecialty==subspecialty, range==rg, year==by); s$percent[1] },
  moe_2023    = { s<-tf %>% filter(subspecialty==subspecialty, range==rg, year==ly); s$percent_moe[1] }
) %>% ungroup() %>% mutate(change_pp = access_2023 - access_2013)

# per-subspec annual trend slope (60-min)
slopes <- tf %>% filter(range == PRIMARY_ACCESS_BAND_SEC) %>% group_by(subspecialty) %>%
  summarise(slope = coef(lm(percent ~ year))[2],
            r2 = summary(lm(percent ~ year))$r.squared,
            p = summary(lm(percent ~ year))$coefficients[2,4], .groups="drop")

cat("=== 60-min access by subspecialty, ", ly, " (PRIMARY) ===\n")
b60 <- res %>% filter(band_min==60) %>% arrange(desc(access_2023))
print(b60 %>% transmute(subspecialty, y2023=round(access_2023,1), y2013=round(access_2013,1),
                        change=round(change_pp,1)), row.names=FALSE)
cat(sprintf("\n60-min range across disciplines: %.1f%% (%s) to %.1f%% (%s)\n",
    min(b60$access_2023), b60$subspecialty[which.min(b60$access_2023)],
    max(b60$access_2023), b60$subspecialty[which.max(b60$access_2023)]))
cat(sprintf("mean across 7 (SECONDARY): %.1f%%\n", mean(b60$access_2023)))

cat("\n=== full subspec x band 2023 matrix ===\n")
m <- res %>% select(subspecialty, band_min, access_2023) %>%
  tidyr::pivot_wider(names_from=band_min, values_from=access_2023)
print(as.data.frame(m %>% mutate(across(where(is.numeric), ~round(.,1)))), row.names=FALSE)

saveRDS(list(matrix=res, slopes=slopes, baseline_year=by, latest_year=ly),
        "scratchpad/manuscript_stage/subspec_access.rds")
cat("\nsaved subspec_access.rds\n")
