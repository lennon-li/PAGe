#!/usr/bin/env Rscript

source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')

if (!requireNamespace('plotly', quietly=TRUE)) stop('Need plotly')
if (!requireNamespace('htmltools', quietly=TRUE)) stop('Need htmltools')

panel <- read.csv('artifacts/v3-joint-ab-audit-v1/canonical_ab_weekly_v3.csv', check.names=FALSE)
lab <- read.csv('artifacts/v3-joint-ab-ignition-review-v1/A_ignition_labels_v3.csv', check.names=FALSE)
breview <- read.csv('artifacts/v3-a-rule-transfer-to-b-v1/B_timing_review_v1.csv', check.names=FALSE)
out_dir <- 'artifacts/v3-a-rule-transfer-to-b-v1'

fit_one <- function(q,type){
  z <- if(type=='A') data.frame(season=q$season,weekF=q$weekF,y=q$y_A,N=q$N_A,p=q$p_A) else data.frame(season=q$season,weekF=q$weekF,y=q$y_B,N=q$N_B,p=q$p_B)
  retrospective_gam_peak_truth(z, season=unique(q$season), k=8L, grid_step=0.01)
}

widgets <- list()
for(s in unique(panel$season)){
  q <- panel[panel$season==s,]; q <- q[order(q$weekF),]
  fa <- fit_one(q,'A'); fb <- fit_one(q,'B')
  ai <- lab$A_ignition_weekF[lab$season==s]

  br <- breview[breview$season==s,,drop=FALSE]
  if(nrow(br)!=1L) stop('Need exactly one B review row for ',s)
  bi <- suppressWarnings(as.numeric(br$B_ignition_weekF))
  b_has_ign <- identical(br$B_ignition_status,'estimated') || identical(br$B_ignition_status,'reviewed')
  b_has_peak <- !identical(br$B_peak_status,'none')

  a_y <- approx(fa$grid$weekF,fa$grid$fitted_p,xout=ai,rule=2)$y*100
  b_y <- if(b_has_ign && is.finite(bi)) approx(fb$grid$weekF,fb$grid$fitted_p,xout=bi,rule=2)$y*100 else NA_real_

  p <- plotly::plot_ly()
  p <- plotly::add_lines(p,data=fa$grid,x=~weekF,y=~(100*fitted_p),name='A GAM fit',line=list(color='#D62728',width=3),hovertemplate='A fit<br>weekF %{x:.2f}<br>%{y:.3f}%<extra></extra>')
  p <- plotly::add_markers(p,data=q,x=~weekF,y=~(100*p_A),name='A observed',marker=list(color='#D62728',size=6),text=~paste0('A: ',y_A,'/',N_A),hovertemplate='A observed<br>weekF %{x}<br>%{y:.3f}%<br>%{text}<extra></extra>')
  p <- plotly::add_lines(p,data=fb$grid,x=~weekF,y=~(100*fitted_p),name='B GAM fit',line=list(color='#1F77B4',width=3),hovertemplate='B fit<br>weekF %{x:.2f}<br>%{y:.3f}%<extra></extra>')
  p <- plotly::add_markers(p,data=q,x=~weekF,y=~(100*p_B),name='B observed',marker=list(color='#1F77B4',size=6,symbol='diamond'),text=~paste0('B: ',y_B,'/',N_B),hovertemplate='B observed<br>weekF %{x}<br>%{y:.3f}%<br>%{text}<extra></extra>')

  p <- plotly::add_markers(p,x=ai,y=a_y,name='A ignition label',marker=list(color='#7A1FA2',size=16,symbol='star'),hovertemplate=paste0('A ignition label<br>weekF ',sprintf('%.1f',ai),'<extra></extra>'))
  if(b_has_ign && is.finite(bi)){
    bname <- if(identical(br$B_ignition_status,'reviewed')) 'B ignition reviewed' else 'B ignition from A rule'
    bhover <- if(identical(br$B_ignition_status,'reviewed')) 'B reviewed ignition' else 'B transferred ignition'
    p <- plotly::add_markers(p,x=bi,y=b_y,name=bname,marker=list(color='#00A6D6',size=16,symbol='star'),hovertemplate=paste0(bhover,'<br>weekF ',sprintf('%.2f',bi),'<extra></extra>'))
  }

  shapes <- list(
    list(type='line',x0=fa$peak_week_decimal,x1=fa$peak_week_decimal,y0=0,y1=1,yref='paper',line=list(color='#D62728',width=1.5,dash='dash'))
  )
  if(b_has_peak){
    shapes[[length(shapes)+1L]] <- list(type='line',x0=fb$peak_week_decimal,x1=fb$peak_week_decimal,y0=0,y1=1,yref='paper',line=list(color='#1F77B4',width=1.5,dash='dash'))
  }

  subtitle <- if(b_has_ign && is.finite(bi)) {
    paste0('B ignition ',sprintf('%.2f',bi),if(identical(br$B_ignition_status,'reviewed')) ' (reviewed)' else ' (A-rule estimate)')
  } else {
    'B ignition: none'
  }
  if(!b_has_peak) subtitle <- paste0(subtitle,' | B peak: none')

  ymax <- 108*max(c(q$p_A,q$p_B,fa$grid$fitted_p,fb$grid$fitted_p),na.rm=TRUE)
  p <- plotly::layout(p,
    title=list(text=paste0(s,' — A label ',sprintf('%.1f',ai),' | ',subtitle)),
    xaxis=list(title='PAGe weekF',dtick=2,showgrid=TRUE),
    yaxis=list(title='Positivity (%)',range=c(0,max(1,ymax)),showgrid=TRUE),
    legend=list(orientation='h',x=0,y=1.11),hovermode='x unified',shapes=shapes,
    margin=list(t=95,b=60,l=70,r=35))
  p <- plotly::config(p,displaylogo=FALSE,responsive=TRUE)
  widgets[[length(widgets)+1L]] <- htmltools::tags$div(style='margin:0 0 34px 0;padding:12px 14px;border:1px solid #ddd;border-radius:8px;',p)
}

page <- htmltools::tags$html(
  htmltools::tags$head(htmltools::tags$title('PAGe v3 A ignition labels and B transfer'),htmltools::tags$style('body{background:#fafafa;margin:20px;font-family:sans-serif;}')),
  htmltools::tags$body(
    htmltools::tags$h1('PAGe v3 — A labels and reviewed B timing'),
    htmltools::tags$p('Purple star = reviewed A ignition label. Cyan star = B ignition (A-rule estimate unless explicitly reviewed). Dashed lines = A/B peaks from the frozen v2 retrospective peak algorithm.'),
    htmltools::tags$p('2017-18 B ignition is manually reviewed at weekF 23.5. 2018-19 is explicitly labeled no B ignition / no B peak because the B trajectory is too flat to support a timing event.'),
    widgets
  )
)
htmltools::save_html(page,file=file.path(out_dir,'A_labels_B_transfer_plotly.html'),libdir='plotly-lib')
cat('Wrote',file.path(out_dir,'A_labels_B_transfer_plotly.html'),'\n')
