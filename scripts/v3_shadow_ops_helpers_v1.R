# Shared operations-only helpers for v2/v3 weekly shadow issuance.
# No model fitting or model-selection logic belongs in this file.

.shadow_ops_sha256 <- function(path) {
  if (!requireNamespace('digest', quietly=TRUE)) stop('Package `digest` is required.', call.=FALSE)
  if (!file.exists(path)) stop('Required file is missing: ',path,call.=FALSE)
  digest::digest(file=path,algo='sha256',serialize=FALSE)
}

.shadow_ops_validate_panel <- function(panel, season, require_forecast_support=FALSE) {
  required <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
  if (!is.data.frame(panel) || !all(required %in% names(panel))) stop('Typed panel schema mismatch.',call.=FALSE)
  if (!nrow(panel)) stop('Typed panel is empty.',call.=FALSE)

  season_vec <- as.character(panel$season)
  if (length(unique(season_vec))!=1L || !identical(unique(season_vec),as.character(season))) {
    stop('Typed panel must contain exactly the requested season.',call.=FALSE)
  }

  week <- as.numeric(panel$weekF)
  if (any(!is.finite(week)) || any(abs(week-round(week))>1e-12)) stop('Typed panel weekF must be finite integers.',call.=FALSE)
  if (anyDuplicated(week)) stop('Typed panel has duplicate weekF.',call.=FALSE)
  if (!identical(order(week),seq_along(week))) stop('Typed panel rows must be sorted by increasing weekF.',call.=FALSE)
  if (length(week)>1L && any(diff(week)!=1)) stop('Typed panel weekF coverage must be contiguous.',call.=FALSE)

  for (tp in c('A','B')) {
    y <- as.numeric(panel[[paste0('y_',tp)]])
    N <- as.numeric(panel[[paste0('N_',tp)]])
    p <- as.numeric(panel[[paste0('p_',tp)]])
    if (any(!is.finite(y)) || any(!is.finite(N)) || any(!is.finite(p)) || any(N<=0) || any(y<0) || any(y>N)) {
      stop('Typed panel has invalid ',tp,' counts/proportions.',call.=FALSE)
    }
    expected <- y/N
    if (max(abs(p-expected))>1e-8) stop('Typed panel ',tp,' proportions do not match y/N.',call.=FALSE)
  }

  regime <- as.character(panel$denominator_regime)
  if (anyNA(regime) || any(!nzchar(regime)) || any(grepl('[\t\r\n]',regime))) stop('Typed panel denominator_regime is invalid.',call.=FALSE)

  has_start <- 'week_start_date' %in% names(panel)
  has_end <- 'week_end_date' %in% names(panel)
  if (xor(has_start,has_end)) stop('Typed panel must contain both week_start_date and week_end_date or neither.',call.=FALSE)
  if (has_start && has_end) {
    ws <- as.Date(panel$week_start_date)
    we <- as.Date(panel$week_end_date)
    if (anyNA(ws) || anyNA(we) || any(we!=ws+6)) stop('Typed panel weekly date bounds are invalid.',call.=FALSE)
    if (length(ws)>1L && any(diff(ws)!=7)) stop('Typed panel week-start dates must be contiguous 7-day intervals.',call.=FALSE)
  }

  origin <- max(week)
  if (isTRUE(require_forecast_support)) {
    required_weeks <- origin-2:0
    if (!all(required_weeks %in% week)) stop('Typed panel lacks exact origin-2:origin support required for forecasting.',call.=FALSE)
  }
  invisible(TRUE)
}

.shadow_ops_effective_panel_payload <- function(panel, season) {
  .shadow_ops_validate_panel(panel,season,require_forecast_support=FALSE)
  date_cols <- if (all(c('week_start_date','week_end_date') %in% names(panel))) c('week_start_date','week_end_date') else character(0)
  cols <- c('season','weekF',date_cols,'y_A','N_A','p_A','y_B','N_B','p_B','denominator_regime')
  x <- panel[,cols,drop=FALSE]
  char_field <- function(v) {
    z <- as.character(v)
    if (any(grepl('[\t\r\n]',z))) stop('Panel field contains tab/newline and cannot be canonically serialized.',call.=FALSE)
    z
  }
  num_field <- function(v) vapply(as.numeric(v),function(q) sprintf('%.17g',q),character(1))
  encoded <- lapply(names(x),function(nm) {
    v <- x[[nm]]
    if (nm %in% c('weekF','y_A','N_A','p_A','y_B','N_B','p_B')) num_field(v) else char_field(v)
  })
  rows <- vapply(seq_len(nrow(x)),function(i) paste(vapply(encoded,`[`,character(1),i),collapse='\t'),character(1))
  paste0(paste(names(x),collapse='\t'),'\n',paste(rows,collapse='\n'),'\n')
}

.shadow_ops_effective_panel_sha256 <- function(panel, season) {
  if (!requireNamespace('digest',quietly=TRUE)) stop('Package `digest` is required.',call.=FALSE)
  digest::digest(.shadow_ops_effective_panel_payload(panel,season),algo='sha256',serialize=FALSE)
}
