# brain-age-prediction-4wave
Brain age prediction code for training and testing using the ABCD Study release 6.0 data (four waves)

## Background

This repo contains two scripts:

| Script | Description |
|--------|-------------|
| **training_validation.R** | Trains a model to predict brain age from imaging features |
| **predict_test_set.R**  | Loads a saved model and evaluates it or predicts on new data |

These scripts are used for brain age testing and training used in \
Beck et al. (https://www.medrxiv.org/content/10.64898/2025.12.31.25343265v2)

## Data preparation

Prepare your data files into two data frames; one for the training (and validation) sample, and one for the hold-out test sample. In my data preparation, I make a Sample1.Rda (loaded in the first script), and a Sample2.Rda (loaded in second script). These two data frames represent a 50:50 cohort split using the ABCD Study data (baseline and two-year follow-up - release 5.1) following QC and longCombat harmonization of imaging data.

The 50:50 split includes a subject-wise split across time-points that ensures baseline and follow-up scans from the same participant remain in the same partition, avoiding identify-confounding. Siblings are dealt with using a group shuffle split with family ID as the group indicator to ensure that no siblings were split across training and test sets. Sex that is not equal to 1 or 2 is removed. The resulting two data frames (sample1 and sample2) represent a final N that is identical (or difference of 1) and has as equal as possible distribution of age range, sex split, and cross-sectional versus longitudinal data points.


## Instructions

### 1. Training
Rscript training_validation.R

In this script, Sample1.Rda is loaded as the training sample following data preparation steps outlined above.
A training/validation split at 80:20 is made (meaning the overarching sample split for training/validation/testing is 40/10/50 percent).


### 2. Test / predict
Rscript predict_test_set.R

In this script, Sample2.Rda (hold-out sample) is loaded as the test set.
Age-bias correction to reduce regression to the mean is carried out using correction procedures outlined in de Lange & Cole (https://doi.org/10.1016/j.nicl.2020.102229).


## Notes

The scripts above use T1-weighted imaging data but scripts are also available for dMRI, rs-fMRI, and a multi-modal model. The figure below shows performance of each model using the code in this repository.
![Brain-age-performance](age_pred_all_models.png)


### Contact
If you have any questions about the code or wish to collaborate, please contact me at [dani.beck@psykologi.uio.no](mailto:dani.beck@psykologi.uio)



