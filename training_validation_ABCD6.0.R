# ──────────────────────────────────────────────────────────────────────
# 1.  Packages & setup, load data
# ──────────────────────────────────────────────────────────────────────

library(dplyr)
library(doParallel)
library(tidymodels)
library(xgboost)

setwd("/path/to/your/directory/")

# Load training sample (Sample 1: 50% of full dataset, family-aware split)
load("Sample1.Rda")

# ──────────────────────────────────────────────────────────────────────
# 2.  Train / Validation split 80/20
# ──────────────────────────────────────────────────────────────────────

set.seed(42)
# Draw 80% of participants (by ID) for the training partition
unique_ids <- unique(sample_1$participant_id)
train_ids  <- sample(unique_ids, size = floor(0.8 * length(unique_ids)))

# Slice the data in a single step each
df_train      <- sample_1 %>% dplyr::filter( participant_id %in% train_ids)
df_validation <- sample_1 %>% dplyr::filter(!participant_id %in% train_ids)

# Save data frames to working directory
save(df_train,      file = "df_train.rds")
save(df_validation, file = "df_validation.rds")

# Clean as you go
rm(sample_1, train_ids, unique_ids)


# ──────────────────────────────────────────────────────────────────────
# 3.  Pre-processing recipe (keeps IDs, drops sex, no early prep)
# ──────────────────────────────────────────────────────────────────────

brainage_recipe <- recipe(ab_g_dyn__visit_age ~ ., data = df_train) %>%
  # Keep identifiers for bookkeeping but exclude from predictors
  update_role(participant_id, session_id, new_role = "id") %>%
  # Drop sex so the model relies purely on brain features
  step_rm(sex) %>%
  # Clean-up steps
  step_nzv(all_predictors()) %>%           # remove near-zero-variance cols
  step_normalize(all_numeric_predictors()) # centre and scale predictors


# ──────────────────────────────────────────────────────────────────────
# 4.  XGBoost model specification and hyper-parameter grid
# ──────────────────────────────────────────────────────────────────────

## 4.1 Fully tunable XGBoost specification
boost_mod <- boost_tree(
  mode           = "regression",
  trees          = tune(),   # 200 – 1200
  tree_depth     = tune(),   # 3 – 10
  min_n          = tune(),   # 2 – 40
  loss_reduction = tune(),   # gamma
  sample_size    = tune(),   # 0.5 – 1.0
  mtry           = tune(),   # maps to colsample_bytree
  learn_rate     = tune()    # 1e-5 – 1e-1
) %>%
  set_engine("xgboost", objective = "reg:squarederror")

## 4.2 Latin hypercube grid (400 candidate parameter sets)
set.seed(42)
xgb_grid <- grid_latin_hypercube(
  trees(range = c(200L, 1200L)),
  tree_depth(range = c(3L, 10L)),
  min_n(range = c(2L, 40L)),
  loss_reduction(),
  sample_size = sample_prop(),
  finalize(mtry(), df_train),
  learn_rate(range = c(-5, -1), trans = scales::log10_trans()),
  size = 400
)


# ──────────────────────────────────────────────────────────────────────
# 5.  Build workflow
# ──────────────────────────────────────────────────────────────────────

xgb_wf <- workflow() %>%
  add_recipe(brainage_recipe) %>%
  add_model(boost_mod)


# ──────────────────────────────────────────────────────────────────────
# 6.  Cross-validation split (5-fold x 2 repeats) and parallel backend
# ──────────────────────────────────────────────────────────────────────

set.seed(42)
train_cv <- vfold_cv(
  df_train,
  v       = 5,
  repeats = 2,
  strata  = ab_g_dyn__visit_age
)

doParallel::registerDoParallel()


# ──────────────────────────────────────────────────────────────────────
# 7.  Hyper-parameter tuning
# Note: this step trains the model across the full grid and may take
# several hours depending on available compute resources.
# ──────────────────────────────────────────────────────────────────────

set.seed(42)
xgb_tuned <- tune_grid(
  xgb_wf,
  resamples = train_cv,
  grid      = xgb_grid,
  metrics   = metric_set(mae, rmse, rsq),
  control   = control_grid(verbose = TRUE, save_pred = TRUE)
)


# ──────────────────────────────────────────────────────────────────────
# 8.  Post-tuning: select best parameters
# ──────────────────────────────────────────────────────────────────────

# Quick leaderboard
show_best(xgb_tuned, metric = "mae", n = 10)

# Select parsimonious parameters within one SE of best MAE
best_xgb_params <- xgb_tuned %>%
  select_by_one_std_err(metric   = "mae",
                        maximize = FALSE,
                        tree_depth)

save(best_xgb_params, file = "best_xgb_params.rds")


# ──────────────────────────────────────────────────────────────────────
# 9.  Final fit and saving
# ──────────────────────────────────────────────────────────────────────

final_xgb    <- finalize_workflow(xgb_wf, best_xgb_params)
fit_workflow <- fit(final_xgb, df_train)

# (A) Workflow object: recipe + model specification (not fitted weights)
save(final_xgb, file = "final_xgb.rds")

# (B) Fully fitted model (weights + workflow) — ready for predict()
save(fit_workflow, file = "fit_workflow.rds")

# (C) Raw XGBoost booster — portable across languages (optional)
model_obj <- fit_workflow$fit$fit$fit
xgb.save(model_obj, "model_obj")
saveRDS(model_obj, file = "xgb_final_mod_RELEASE_6.0.rds")
