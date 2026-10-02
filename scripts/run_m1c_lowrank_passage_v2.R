d <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
shape <- read.csv('artifacts/m1-peak-aligned-shape-v1/peak_aligned_smoothed_grid.csv', stringsAsFactors=FALSE)
peaks <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
m0cmp <- read.csv('artifacts/m0-v2-decimal-loso-baseline-r2/compare.csv', stringsAsFactors=FALSE)
Amap <- setNames(m0cmp$iWeek_hatF,m0cmp$season)
Tmap <- setNames(peaks$peak_week_decimal,peaks$season)
seasons <- intersect(names(Amap),names(Tmap))

peak_height <- tapply(shape$p_smooth,shape$season,max,na.rm=TRUE)
shape$p_norm <- shape$p_smooth/peak_height[shape$season]
# M1-C needs the early decline, unlike M1-F.
tau_grid <- seq(-14,3,by=.1)
M <- matrix(NA_real_,nrow=length(seasons),ncol=length(tau_grid),dimnames=list(seasons,NULL))
for(i in seq_along(seasons)){
  z <- shape[shape$season==seasons[i],]
  M[i,] <- approx(z$tau,z$p_norm,xout=tau_grid,rule=1)$y
}

library_for <- function(holdout){
  keep <- seasons!=holdout
  X <- M[keep,,drop=FALSE]
  # Fill rare edge NA values column-wise before PCA.
  for(j in seq_len(ncol(X))){
    if(anyNA(X[,j])) X[is.na(X[,j]),j] <- median(X[,j],na.rm=TRUE)
  }
  pc <- prcomp(X,center=TRUE,scale.=FALSE)
  mean_curve <- pc$center
  loading <- pc$rotation[,1]
  scores <- pc$x[,1]
  recon <- sweep(outer(scores,loading),2,mean_curve,'+')
  resid <- X-recon
  bh <- peak_height[seasons[keep]]
  list(tau=tau_grid,mean=mean_curve,pc1=loading,resid_sd=pmax(apply(resid,2,sd),.025),
       sd_c=max(sd(scores),.2),mu_logb=mean(log(bh)),sd_logb=max(sd(log(bh)),.2))
}

log_evidence_T <- function(obs,Tcan,lib,bgrid,cgrid){
  tau <- obs$weekF-Tcan
  if(any(tau<min(lib$tau)|tau>max(lib$tau))) return(-Inf)
  f0 <- approx(lib$tau,lib$mean,xout=tau)$y
  pcv <- approx(lib$tau,lib$pc1,xout=tau)$y
  rsd <- approx(lib$tau,lib$resid_sd,xout=tau)$y
  bc <- expand.grid(b=bgrid,c=cgrid)
  F <- matrix(f0,nrow=nrow(bc),ncol=length(f0),byrow=TRUE)+outer(bc$c,pcv)
  F <- pmin(pmax(F,.001),1.30)
  MU <- F*bc$b
  VV <- (outer(bc$b,rsd))^2 + MU*(1-MU)/matrix(pmax(obs$N,1),nrow=nrow(bc),ncol=nrow(obs),byrow=TRUE)
  VV <- pmax(VV,1e-6)
  YY <- matrix(obs$p,nrow=nrow(bc),ncol=nrow(obs),byrow=TRUE)
  data_nll2 <- rowSums((YY-MU)^2/VV+log(VV))
  prior_b <- ((log(bc$b)-lib$mu_logb)/lib$sd_logb)^2+2*log(bc$b)
  prior_c <- (bc$c/lib$sd_c)^2
  S <- data_nll2+prior_b+prior_c
  m <- min(S)
  -.5*m+log(sum(exp(-.5*(S-m))))
}

bgrid <- seq(.08,.44,by=.02)
rows <- list()
for(s in seasons){
  dd <- d[d$season==s,];dd<-dd[order(dd$weekF),]
  A<-Amap[[s]];Ttrue<-Tmap[[s]];lib<-library_for(s)
  cgrid<-seq(-2.5*lib$sd_c,2.5*lib$sd_c,length.out=15)
  # Candidate-independent passage ledger: activation through truth peak+2.
  origins<-seq(ceiling(A),min(max(dd$weekF),ceiling(Ttrue)+2),1)
  for(o in origins){
    obs<-dd[dd$weekF>=ceiling(A)&dd$weekF<=o,]
    # Permit candidate peaks up to 3 weeks in past and 12 weeks future.
    cands<-seq(max(A+3,o-3),min(o+12,40),by=.1)
    le<-vapply(cands,function(tc)log_evidence_T(obs,tc,lib,bgrid,cgrid),numeric(1))
    ok<-is.finite(le); if(!any(ok))next
    le[!ok]<- -Inf; w<-exp(le-max(le));w<-w/sum(w)
    p_passed<-sum(w[cands<=o])
    p_within1<-sum(w[cands>o & cands<=o+1])
    p_within2<-sum(w[cands>o & cands<=o+2])
    rows[[length(rows)+1]]<-data.frame(season=s,A=A,origin=o,true_peak=Ttrue,truth_confirm=ceiling(Ttrue),
      p_passed=p_passed,p_within1=p_within1,p_within2=p_within2,post_truth=o>=ceiling(Ttrue))
  }
}
out<-do.call(rbind,rows)
dir.create('artifacts/m1-c-passage-lowrank-v2',recursive=TRUE,showWarnings=FALSE)
write.csv(out,'artifacts/m1-c-passage-lowrank-v2/per_origin_posterior.csv',row.names=FALSE)

# Candidate passage policies: posterior threshold + required consecutive origins.
policies<-expand.grid(threshold=c(.5,.6,.7,.8,.9,.95),persistence=c(1,2),min_post_A=c(2,3,4),KEEP.OUT.ATTRS=FALSE)
policies$policy_id<-seq_len(nrow(policies))
apply_policy<-function(s,pol){
  z<-out[out$season==s,];z<-z[order(z$origin),]
  confirm<-NA_real_
  for(i in seq_len(nrow(z))){
    if(z$origin[i] < ceiling(Amap[[s]])+pol$min_post_A)next
    if(i<pol$persistence)next
    vals<-tail(z$p_passed[seq_len(i)],pol$persistence)
    if(all(vals>=pol$threshold)){confirm<-z$origin[i];break}
  }
  tc<-ceiling(Tmap[[s]])
  data.frame(season=s,policy_id=pol$policy_id,confirm_origin=confirm,truth_confirm=tc,
    false_early=is.finite(confirm)&&confirm<tc,
    delay=if(is.finite(confirm))max(confirm-tc,0) else NA_real_,
    confirmed_by_peak2=is.finite(confirm)&&confirm<=tc+2,
    miss_by_peak2=!is.finite(confirm)||confirm>tc+2)
}
allpol<-do.call(rbind,lapply(seq_len(nrow(policies)),function(i)do.call(rbind,lapply(seasons,function(s)apply_policy(s,policies[i,])))))
allpol<-merge(allpol,policies,by='policy_id',sort=FALSE)
write.csv(allpol,'artifacts/m1-c-passage-lowrank-v2/policy_all_seasons.csv',row.names=FALSE)

# LOSO selection; false early dominates, then miss by +2, then delay, then conservative threshold/persistence.
selected<-list()
for(h in seasons){
  tr<-allpol[allpol$season!=h,]
  agg<-do.call(rbind,lapply(split(tr,tr$policy_id),function(x)data.frame(policy_id=x$policy_id[1],
    n_false_early=sum(x$false_early),n_miss=sum(x$miss_by_peak2),
    mean_delay=if(any(is.finite(x$delay)))mean(x$delay[is.finite(x$delay)]) else Inf,
    threshold=x$threshold[1],persistence=x$persistence[1],min_post_A=x$min_post_A[1])))
  ord<-order(agg$n_false_early,agg$n_miss,agg$mean_delay,-agg$threshold,-agg$persistence,-agg$min_post_A)
  best<-agg[ord[1],]
  te<-allpol[allpol$season==h&allpol$policy_id==best$policy_id,]
  selected[[h]]<-cbind(te,train_false_early=best$n_false_early,train_miss=best$n_miss,train_delay=best$mean_delay)
}
loso<-do.call(rbind,selected);rownames(loso)<-NULL
write.csv(loso,'artifacts/m1-c-passage-lowrank-v2/loso_selected.csv',row.names=FALSE)
cat('LOSO PASSAGE\n');print(loso[,c('season','threshold','persistence','min_post_A','truth_confirm','confirm_origin','false_early','delay','miss_by_peak2')],row.names=FALSE,digits=3)
cat('\nSUMMARY\n');cat('false early=',sum(loso$false_early),'/',nrow(loso),' confirmed by +2=',sum(loso$confirmed_by_peak2),'/',nrow(loso),' miss=',sum(loso$miss_by_peak2),' mean delay=',mean(loso$delay[is.finite(loso$delay)]),' median delay=',median(loso$delay[is.finite(loso$delay)]),'\n',sep='')
