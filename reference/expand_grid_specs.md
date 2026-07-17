# Expand a hyperparameter grid into Stage-2 spec objects (ALL hyperparams can vary)

Creates a cartesian product over all supplied grids and returns:

- a named list of `spec` objects (`$specs`)

- a data.frame describing the grid (`$grid`)

## Usage

``` r
expand_grid_specs(
  delta_grid = -3:3,
  Kr_grid = 1:6,
  T_grid = c("O", "S"),
  k_f_grid = c(6L, 8L, 10L),
  alpha_state = c(0.25),
  Kb_grid = c(0L, 1L),
  leads = c(1L, 2L),
  k_w_grid = c(8L),
  k_s_grid = c(0L),
  k_e_grid = c(6L),
  k_n_grid = c(6L),
  k_de_grid = c(0L),
  k_r_grid = c(0L),
  bs_week_grid = "ts",
  bs_fs_marginal_grid = "tp",
  bias_alpha_grid = c(0.4),
  bias_beta_grid = c(0),
  drop_unused_kf_for_nonS = TRUE,
  verbose = TRUE
)
```

## Arguments

- delta_grid:

  Integer vector.

- Kr_grid:

  Integer vector for ramp length.

- T_grid:

  Character vector in `c("O","S","N")`.

- k_f_grid:

  Integer vector (used only when `T=="S"`).

- alpha_state:

  Numeric vector in (0,1).

- Kb_grid:

  Integer vector for ignition buffer length.

- leads:

  Integer vector of horizons (typically fixed to `c(1L,2L)`).

- k_w_grid, k_s_grid, k_e_grid, k_n_grid, k_de_grid:

  Integer vectors for smooth basis sizes.

- k_r_grid:

  Integer vector for residual-smooth basis sizes.

- bs_week_grid:

  Character vector for week smooth basis.

- bs_fs_marginal_grid:

  Character vector for fs marginal basis.

- bias_alpha_grid, bias_beta_grid:

  Numeric vectors for Holt correction rates.

- drop_unused_kf_for_nonS:

  If TRUE, sets `k_f=NA` for `T!="S"`.

- verbose:

  Logical.

## Value

List with `specs`, `grid`, and `n`.

## Details

Special handling:

- `k_f` is only meaningful when `T=="S"`. For `T!="S"`, `k_f` is set to
  NA by default to avoid unnecessary expansion.
