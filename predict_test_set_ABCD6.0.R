# ──────────────────────────────────────────────────────────────────────
# 1.  Packages and working directory
# ──────────────────────────────────────────────────────────────────────

library(tidymodels)
library(xgboost)

setwd("/path/to/your/directory/")

# ──────────────────────────────────────────────────────────────────────
# 2.  Load fitted artefacts produced by the training script
# ──────────────────────────────────────────────────────────────────────

load("fit_workflow.rds")  # brings object `fit_workflow`
fit_workflow

load("final_xgb.rds")     # object `final_xgb` (optional, spec only)
final_xgb

# ──────────────────────────────────────────────────────────────────────
# 3.  Load hold-out sample (50% split)
# ──────────────────────────────────────────────────────────────────────

load("Sample2.Rda")

# ──────────────────────────────────────────────────────────────────────
# 4.  Predict brain age in the hold-out cohort (Sample 2)
# ──────────────────────────────────────────────────────────────────────

# Predict and assemble brain-age data frame with metadata
brain_age_pred <- predict(fit_workflow, new_data = sample_2) %>%
  dplyr::bind_cols(
    sample_2 %>%
      dplyr::select(participant_id,       # participant ID
                    session_id,           # time-point / visit label
                    sex,                  # biological sex
                    ab_g_dyn__visit_age)  # chronological age
  ) %>%
  dplyr::rename(truth = ab_g_dyn__visit_age) %>%
  dplyr::mutate(gap = .pred - truth) %>%
  dplyr::select(participant_id, session_id, sex,
                truth, .pred, gap)

# Performance check on the hold-out sample
brain_age_pred %>%
  yardstick::metrics(truth = truth, estimate = .pred)


# ──────────────────────────────────────────────────────────────────────
# 5.  Age-bias correction based on the validation (20%) split
# ──────────────────────────────────────────────────────────────────────

load("df_validation.rds")

val_pred <- predict(fit_workflow, new_data = df_validation) %>%
  dplyr::mutate(truth = df_validation$ab_g_dyn__visit_age)

bias_mod       <- lm(.pred ~ truth, data = val_pred)
bias_intercept <- coef(bias_mod)[1]
bias_slope     <- coef(bias_mod)[2]

# Apply correction to hold-out predictions
brain_age_pred <- brain_age_pred %>%
  dplyr::mutate(
    corrected_pred = (.pred - bias_intercept) / bias_slope,
    corrected_gap  = corrected_pred - truth
  ) %>%
  dplyr::select(participant_id, session_id, sex,
                truth, .pred, corrected_pred,
                gap,   corrected_gap)


# ──────────────────────────────────────────────────────────────────────
# 6.  Save results
# ──────────────────────────────────────────────────────────────────────

save(brain_age_pred, file = "abcd_6.0_T1_brain_age.rds")


# ──────────────────────────────────────────────────────────────────────
# 7.  Sanity checks
# ──────────────────────────────────────────────────────────────────────

# Correlation between corrected GAP and age should approach zero
brain_age_pred %>%
  summarise(r = cor(corrected_gap, truth))

# Plot raw predictions vs chronological age
library(ggplot2)
ggplot(brain_age_pred, aes(truth, .pred)) +
  geom_point(alpha = .1) +
  geom_abline(lty = 2) +
  geom_abline(intercept = bias_intercept, slope = bias_slope, colour = "red") +
  labs(title = "Calibration: raw (red) vs ideal (black dashed)")

# Plot bias-corrected predictions vs chronological age
ggplot(brain_age_pred, aes(truth, corrected_pred)) +
  geom_point(alpha = .1) +
  geom_abline(lty = 2) +
  labs(title = "After bias correction")