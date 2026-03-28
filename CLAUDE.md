## PAGe Project

When working on the PAGe forecasting project, always check that lead format (e.g., numeric vs string like `lead_1`) is consistent across filtering, plotting, and data processing functions before making changes.

## System Commands

To shut down the Windows computer from bash, use:
```bash
cmd.exe /c "shutdown /s /t 0"
```
`shutdown -now` does **not** work on Windows. Always confirm exact syntax with the user before running any system/shutdown command.

# Project Objective

**Develop a model and R package for seasonal respiratory virus percentage positivity forecasting.**

## Primary Goal
Accurately forecast the **percentage positivity of seasonal respiratory viruses (e.g., influenza) 2 weeks ahead**, using surveillance data. Every piece of work in this project — modeling, alignment, training, evaluation, documentation — exists to serve this forecasting objective.

## Deliverables
1. **Forecasting model** — a trained, validated model for 2-week-ahead % positivity prediction
2. **`flualign` R package** — a clean, documented, installable R package implementing the model pipeline for end-user deployment

## Guiding Principles for All Work
- Model accuracy and calibration for the 2-week forecast horizon are the primary success criteria
- All design decisions (feature engineering, alignment methods, tuning, evaluation) should be justified by their contribution to forecast accuracy
- The R package must be usable by practitioners — prioritize clean APIs, robust defaults, and good documentation
- Evaluation should be prospective/walk-forward (no data leakage from future seasons)
