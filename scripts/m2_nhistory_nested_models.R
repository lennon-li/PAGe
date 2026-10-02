nh_n_columns <- function(n_option, protocol = nh_protocol()) {
  row <- nh_n_options(protocol)
  row <- row[row$n_option == n_option, , drop=FALSE]
  if (nrow(row) != 1L) stop("Unknown N option: ", n_option, call.=FALSE)
  if (identical(n_option, "OFF")) return(character())
  strsplit(as.character(row$columns), "+", fixed=TRUE)[[1L]]
}

nh_prepare_m2_rows <- function(rows, require_outcome=TRUE) {
  x <- as.data.frame(rows)
  required <- c("row_season","horizon","m1_p_hat","m1_logit","z","u","d",
                "tau","peak_weekF_lo","peak_weekF_hi")
  if(isTRUE(require_outcome)) required <- c(required,"y_target","N_target")
  miss <- setdiff(required,names(x)); if(length(miss)) stop("M2 rows missing: ",paste(miss,collapse=", "),call.=FALSE)
  x$season <- as.character(x$row_season)
  x$lead <- factor(paste0("h",as.integer(x$horizon)),levels=c("h1","h2"))
  if(isTRUE(require_outcome)) {
    x$y_lead <- as.numeric(x$y_target); x$N_lead <- as.numeric(x$N_target)
  }
  x$m1_p <- as.numeric(x$m1_p_hat)
  x$peak_ci_width <- as.numeric(x$peak_weekF_hi)-as.numeric(x$peak_weekF_lo)
  x
}

nh_formula_n <- function(spec, n_cols, bs="ts") {
  base <- paste(deparse(m2_subset_formula(spec,bs=bs)),collapse=" ")
  if (!length(n_cols)) return(stats::as.formula(base))
  stats::as.formula(paste(base, "+", paste(n_cols,collapse=" + ")))
}

nh_apply_ranges <- function(data,ranges){
  x<-as.data.frame(data); for(nm in names(ranges)){if(!nm%in%names(x))stop("Prediction missing ",nm,call.=FALSE); r<-ranges[[nm]]; x[[nm]]<-pmin(r[2],pmax(r[1],as.numeric(x[[nm]])))};x
}

nh_fit <- function(data,spec,n_option="OFF",method="REML",gamma=1.4,bs="ts",intercept_sp=-1,protocol=nh_protocol()){
  nh_load_page_source(); dat<-nh_prepare_m2_rows(data); sp<-m2_subset_spec(spec); ncols<-nh_n_columns(n_option,protocol)
  if(identical(n_option,"OFF")) return(list(kind="OFF",base=m2_subset_fit(dat,sp,method=method,gamma=gamma,bs=bs),n_option=n_option))
  if(any(!ncols%in%names(dat))) stop("N option columns missing: ",paste(setdiff(ncols,names(dat)),collapse=", "),call.=FALSE)
  if(any(!vapply(dat[ncols],function(z)all(is.finite(z)),logical(1)))) stop("N covariates non-finite.",call.=FALSE)
  dat$lead<-factor(as.character(dat$lead),levels=c("h1","h2")); if(any(table(dat$lead)==0))stop("Both horizons required.",call.=FALSE)
  base_ranges<-m2_subset_feature_ranges(dat,sp); nr<-lapply(ncols,function(nm)range(as.numeric(dat[[nm]]),na.rm=TRUE));names(nr)<-ncols;ranges<-c(base_ranges,nr)
  widths<-dat$peak_ci_width; wref<-if(sp$conf_scale=="peak_ci")stats::median(widths[is.finite(widths)&widths>0],na.rm=TRUE)else NA_real_
  conf<-.m2_subset_confidence(dat,sp$conf_scale,wref); if(sp$conf_scale=="peak_ci"&&(!is.finite(wref)||wref<=0))stop("peak_ci requires positive training width median.",call.=FALSE)
  totals<-tapply(dat$N_lead,dat$season,sum); if(any(!is.finite(totals)|totals<=0))stop("Bad season totals.",call.=FALSE)
  dat$.fit_weight<-unname(mean(totals)/totals[dat$season]); formula<-nh_formula_n(sp,ncols,bs)
  para_pen<-if(isTRUE(sp$intercept))list(lead=list(diag(2L),sp=intercept_sp))else NULL
  warnings<-character(); fit<-withCallingHandlers({
    if(sp$conf_scale=="peak_ci") .m2_subset_fit_scaled_gam(formula,dat,stats::binomial(),method,gamma,dat$.fit_weight,para_pen,conf$scale)
    else mgcv::gam(formula,data=dat,family=stats::binomial(),method=method,gamma=gamma,select=TRUE,weights=.fit_weight,paraPen=para_pen,na.action=stats::na.fail)
  },warning=function(w){warnings<<-unique(c(warnings,conditionMessage(w)));invokeRestart("muffleWarning")})
  if(!m2_subset_is_converged(fit))stop("N-enabled GAM did not converge.",call.=FALSE); .m2_subset_check_fit_method(fit,method)
  list(kind="N",fit=fit,spec=sp,n_option=n_option,n_cols=ncols,formula=formula,feature_ranges=ranges,
       conf_scale=sp$conf_scale,w_ref=wref,training_seasons=sort(unique(dat$season)),season_trial_totals=totals,
       fit_weight_by_season=mean(totals)/totals,warnings=warnings,method=method,gamma=gamma)
}

nh_predict <- function(fit,newdata){
  nh_load_page_source(); nd<-nh_prepare_m2_rows(newdata,require_outcome=FALSE)
  if(identical(fit$kind,"OFF")) return(m2_subset_predict(fit$base,nd))
  nd<-nh_apply_ranges(nd,fit$feature_ranges); conf<-.m2_subset_confidence(nd,fit$conf_scale,fit$w_ref)
  if(fit$conf_scale=="peak_ci"){
    lp<-stats::predict(fit$fit,newdata=nd,type="lpmatrix");lp<-.m2_subset_scale_design_rows(lp,conf$scale);eta<-as.numeric(lp%*%stats::coef(fit$fit))+nd$m1_logit
  }else eta<-as.numeric(stats::predict(fit$fit,newdata=nd,type="link"))
  corr<-pmin(10,pmax(-10,eta-nd$m1_logit)); eta<-nd$m1_logit+corr
  data.frame(p_hat=stats::plogis(eta),m1_p=nd$m1_p,correction_logit=corr,confidence_scale=conf$scale,stringsAsFactors=FALSE)
}

nh_smoke_grid <- function(protocol=nh_protocol()){
  data.frame(spec_id=c("all_off","nontrivial","tau_conf"),intercept=c(FALSE,TRUE,TRUE),k_z=c(0L,3L,3L),k_u=c(0L,0L,0L),k_d=c(0L,3L,3L),k_tau=c(0L,0L,3L),conf_scale=c("none","none","peak_ci"),alpha_state=0.2,gamma=1.4,stringsAsFactors=FALSE)
}
