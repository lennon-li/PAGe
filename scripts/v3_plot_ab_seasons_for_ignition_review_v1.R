#!/usr/bin/env Rscript

# PAGe v3 A/B ignition-review plots.
# Research-only: reads the canonical paired v3 panel and applies the frozen
# retrospective v2 peak-truth algorithm independently to A and B.

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')

if (!requireNamespace('plotly', quietly=TRUE)) stop('Package `plotly` is required.')
if (!requireNamespace('htmltools', quietly=TRUE)) stop('Package `htmltools` is required.')

in_path <- 'artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv'
out_dir <- 'artifacts/v3-joint-ab-ignition-review-v1'
dir.create(out_dir, recursive=TRUE, showWarnings=FALSE)
stopifnot(file.exists(in_path))

ab <- read.csv(in_path, stringsAsFactors=FALSE, check.names=FALSE)
req <- c('season','weekF','y_A','N_A','p_A','y_B','N_B','p_B')
if (!all(req %in% names(ab))) stop('Canonical panel is missing required fields.')

seasons <- unique(ab$season)
peak_rows <- list()
widgets <- list()

fit_one <- function(q, type) {
  if (type == 'A') {
    z <- data.frame(season=q$season, weekF=q$weekF, y=q$y_A, N=q$N_A, p=q$p_A)
  } else {
    z <- data.frame(season=q$season, weekF=q$weekF, y=q$y_B, N=q$N_B, p=q$p_B)
  }
  retrospective_gam_peak_truth(z, season=unique(q$season), k=8L, grid_step=0.01)
}

for (s in seasons) {
  q <- ab[ab$season == s, , drop=FALSE]
  q <- q[order(q$weekF), , drop=FALSE]
  fa <- fit_one(q, 'A')
  fb <- fit_one(q, 'B')

  peak_rows[[length(peak_rows)+1L]] <- data.frame(
    season=s,
    A_peak_weekF=fa$peak_week_decimal,
    A_peak_fitted_p=fa$peak_fitted_p,
    B_peak_weekF=fb$peak_week_decimal,
    B_peak_fitted_p=fb$peak_fitted_p,
    peak_method='retrospective-gam-peak-v1-k8',
    grid_step=0.01,
    stringsAsFactors=FALSE
  )

  ymax <- max(c(q$p_A, q$p_B, fa$grid$fitted_p, fb$grid$fitted_p), na.rm=TRUE)
  ymax <- max(0.01, 1.08 * ymax)

  p <- plotly::plot_ly()
  p <- plotly::add_lines(
    p, data=fa$grid, x=~weekF, y=~(100*fitted_p),
    name='A GAM fit', line=list(color='#D62728', width=3),
    hovertemplate='A fit<br>weekF %{x:.2f}<br>%{y:.3f}%<extra></extra>'
  )
  p <- plotly::add_markers(
    p, data=q, x=~weekF, y=~(100*p_A),
    name='A observed', marker=list(color='#D62728', size=7, symbol='circle'),
    text=~paste0('A: ', y_A, '/', N_A),
    hovertemplate='A observed<br>weekF %{x}<br>%{y:.3f}%<br>%{text}<extra></extra>'
  )
  p <- plotly::add_lines(
    p, data=fb$grid, x=~weekF, y=~(100*fitted_p),
    name='B GAM fit', line=list(color='#1F77B4', width=3),
    hovertemplate='B fit<br>weekF %{x:.2f}<br>%{y:.3f}%<extra></extra>'
  )
  p <- plotly::add_markers(
    p, data=q, x=~weekF, y=~(100*p_B),
    name='B observed', marker=list(color='#1F77B4', size=7, symbol='diamond'),
    text=~paste0('B: ', y_B, '/', N_B),
    hovertemplate='B observed<br>weekF %{x}<br>%{y:.3f}%<br>%{text}<extra></extra>'
  )

  p <- plotly::layout(
    p,
    title=list(text=paste0(
      s,
      ' — A peak ', sprintf('%.2f', fa$peak_week_decimal),
      ' | B peak ', sprintf('%.2f', fb$peak_week_decimal)
    )),
    xaxis=list(title='PAGe weekF', dtick=2, showgrid=TRUE),
    yaxis=list(title='Positivity (%)', range=c(0, 100*ymax), showgrid=TRUE),
    legend=list(orientation='h', x=0, y=1.10),
    hovermode='x unified',
    shapes=list(
      list(type='line', x0=fa$peak_week_decimal, x1=fa$peak_week_decimal,
           y0=0, y1=1, yref='paper', line=list(color='#D62728', width=2, dash='dash')),
      list(type='line', x0=fb$peak_week_decimal, x1=fb$peak_week_decimal,
           y0=0, y1=1, yref='paper', line=list(color='#1F77B4', width=2, dash='dash'))
    ),
    annotations=list(
      list(x=fa$peak_week_decimal, y=1, yref='paper', text=paste0('A peak ', sprintf('%.2f', fa$peak_week_decimal)),
           showarrow=FALSE, xanchor='right', yanchor='bottom', font=list(color='#D62728')),
      list(x=fb$peak_week_decimal, y=0.93, yref='paper', text=paste0('B peak ', sprintf('%.2f', fb$peak_week_decimal)),
           showarrow=FALSE, xanchor='left', yanchor='bottom', font=list(color='#1F77B4'))
    ),
    margin=list(t=95, b=60, l=70, r=35)
  )
  p <- plotly::config(p, displaylogo=FALSE, responsive=TRUE)

  widgets[[length(widgets)+1L]] <- htmltools::tags$div(
    style='margin: 0 0 34px 0; padding: 12px 14px; border: 1px solid #ddd; border-radius: 8px;',
    p
  )
}

peaks <- do.call(rbind, peak_rows)
write.csv(peaks, file.path(out_dir, 'peak_truth_v2_algorithm_ab.csv'), row.names=FALSE)

intro <- htmltools::tags$div(
  style='font-family: sans-serif; max-width: 1450px; margin: 0 auto;',
  htmltools::tags$h1('PAGe v3 A/B ignition review'),
  htmltools::tags$p('Each season shows observed influenza A and B positivity plus separate retrospective GAM fits.'),
  htmltools::tags$p('Dashed vertical lines are peak truth from the frozen v2 algorithm: quasibinomial GAM, cubic regression spline, k=8, REML, 0.01-week peak grid.'),
  htmltools::tags$p('No ignition lines are shown yet. Use the hoverable weekF axis to choose A and B ignition labels.'),
  widgets
)

page <- htmltools::tagList(
  htmltools::tags$html(
    htmltools::tags$head(
      htmltools::tags$title('PAGe v3 A/B ignition review'),
      htmltools::tags$style('body { background:#fafafa; margin:20px; }')
    ),
    htmltools::tags$body(intro)
  )
)

htmltools::save_html(page, file=file.path(out_dir, 'index.html'), libdir='lib')
cat('Wrote:', file.path(out_dir, 'index.html'), '\n')
cat('Wrote:', file.path(out_dir, 'peak_truth_v2_algorithm_ab.csv'), '\n')
cat('Seasons:', length(seasons), '\n')
