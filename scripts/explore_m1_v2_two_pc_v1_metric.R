source('PAGe/R/data_contract.R')
source('PAGe/R/expert_timing_annotations.R')
source('PAGe/R/retrospective_peak_truth.R')

campaign <- readRDS('artifacts/expert-ignition-annotation-v2-pass1/campaign_data.rds')
current_truth <- read.csv('artifacts/expert-ignition-annotation-v2-pass1/retrospective_peak_truth_v1.csv', stringsAsFactors=FALSE)
contract_dir <- '../PAGe/results/benchmark-contracts/m1/v1.0.0'
origin <- read.csv(file.path(contract_dir,'origin_ledger.csv'),stringsAsFactors=FALSE)
m0 <- read.csv(file.path(contract_dir,'m0_origin_ledger.csv'),stringsAsFactors=FALSE)
frozen_truth <- read.csv(file.path(contract_dir,'peak_truth_ledger.csv'),stringsAsFactors=FALSE)
seasons <- as.character(frozen_truth$season)
primary <- origin[origin$in_primary_prepeak,]
primary <- merge(primary,m0[,c('season','origin_weekF','m0_locked_weekF')],by=c('season','origin_weekF'),all.x=TRUE,sort=FALSE)

tau_grid <- seq(-14,0,by=.1)
bgrid <- seq(.08,.44,by=.025)

fit_lib2 <- function(train_seasons){
  X <- matrix(NA_real_,nrow=length(train_seasons),ncol=length(tau_grid),dimnames=list(train_seasons,NULL))
  amp <- numeric(length(train_seasons)); names(amp)<-train_seasons
  for(i in seq_along(train_seasons)){
    s <- train_seasons[i]
    f <- retrospective_gam_peak_truth(campaign,season=s,k=8,grid_step=.01)
    truth <- current_truth$peak_week_decimal[current_truth$season==s]
    g <- f$grid; g$tau <- g$weekF-truth; a <- max(g$fitted_p); amp[s]<-a
    X[i,] <- approx(g$tau,g$fitted_p/a,xout=tau_grid,rule=1)$y
  }
  pc <- prcomp(X,center=TRUE,scale.=FALSE)
  mu <- pc$center; L1<-pc$rotation[,1];L2<-pc$rotation[,2]
  sd1<-max(sd(pc$x[,1]),.2); sd2<-max(sd(pc$x[,2]),.05)
  recon <- sweep(pc$x[,1:2,drop=FALSE] %*% t(pc$rotation[,1:2,drop=FALSE]),2,mu,'+')
  rsd <- pmax(apply(X-recon,2,sd),.02)
  c1 <- seq(-2.5*sd1,2.5*sd1,length.out=13)
  c2 <- seq(-2.5*sd2,2.5*sd2,length.out=11)
  cc <- expand.grid(c1=c1,c2=c2)
  i0 <- length(tau_grid)
  ok <- vapply(seq_len(nrow(cc)),function(i){ff<-mu+cc$c1[i]*L1+cc$c2[i]*L2; ff[i0]>=max(ff)-1e-6},logical(1))
  cc <- cc[ok,,drop=FALSE]
  list(tau=tau_grid,mu=mu,L1=L1,L2=L2,sd1=sd1,sd2=sd2,rsd=rsd,cc=cc,
       mu_logb=mean(log(amp)),sd_logb=max(sd(log(amp)),.2),
       var2=sum(pc$sdev[1:2]^2)/sum(pc$sdev^2))
}

logev <- function(obs,T,lib){
  tau <- obs$weekF-T
  if(any(tau<min(lib$tau)|tau>max(lib$tau))) return(-Inf)
  f0<-approx(lib$tau,lib$mu,xout=tau)$y
  l1<-approx(lib$tau,lib$L1,xout=tau)$y
  l2<-approx(lib$tau,lib$L2,xout=tau)$y
  rs<-approx(lib$tau,lib$rsd,xout=tau)$y
  cc<-lib$cc
  F <- matrix(f0,nrow=nrow(cc),ncol=length(f0),byrow=TRUE)+outer(cc$c1,l1)+outer(cc$c2,l2)
  F <- pmax(F,.001)
  # integrate amplitude within each shape combination
  scores <- numeric(0)
  for(b in bgrid){
    MU<-F*b
    VV<-(b*matrix(rs,nrow=nrow(cc),ncol=length(rs),byrow=TRUE))^2 + MU*(1-MU)/matrix(pmax(obs$N,1),nrow=nrow(cc),ncol=nrow(obs),byrow=TRUE)
    VV<-pmax(VV,1e-6)
    YY<-matrix(obs$p,nrow=nrow(cc),ncol=nrow(obs),byrow=TRUE)
    s<-rowSums((YY-MU)^2/VV+log(VV)) + ((log(b)-lib$mu_logb)/lib$sd_logb)^2+2*log(b)+(cc$c1/lib$sd1)^2+(cc$c2/lib$sd2)^2
    scores<-c(scores,s)
  }
  m<-min(scores); -.5*m+log(sum(exp(-.5*(scores-m))))
}

rows<-list(); libmeta<-list()
for(h in seasons){
  train<-setdiff(seasons,h);lib<-fit_lib2(train);libmeta[[h]]<-data.frame(season=h,n_shape=nrow(lib$cc),var2=lib$var2)
  held<-prepare_surveillance_data(campaign[campaign$season==h,]);rr<-primary[primary$season==h,];A<-unique(rr$m0_locked_weekF)
  for(i in seq_len(nrow(rr))){
    o<-rr$origin_weekF[i]; obs<-held[held$weekF>=ceiling(A)&held$weekF<=o,]
    asof<-o+1; upper<-min(asof+14,min(obs$weekF)+14);cands<-seq(asof+.05,upper,by=.1)
    le<-vapply(cands,function(T)logev(obs,T,lib),numeric(1));w<-exp(le-max(le));w<-w/sum(w);cdf<-cumsum(w)
    rows[[length(rows)+1]]<-data.frame(season=h,origin=o,m0=A,mean=sum(cands*w),median=cands[which(cdf>=.5)[1]],map=cands[which.max(w)])
  }
}
x<-do.call(rbind,rows);meta<-do.call(rbind,libmeta)
x<-merge(x,frozen_truth[,c('season','peak_integer_weekF','peak_decimal_weekF')],by='season',all.x=TRUE,sort=FALSE)
x<-merge(x,current_truth[,c('season','peak_week_decimal')],by='season',all.x=TRUE,sort=FALSE);names(x)[names(x)=='peak_week_decimal']<-'current_peak_decimal';x$current_peak_integer<-round(x$current_peak_decimal);x$weight<-exp(-(0.1*(x$origin-x$m0))^2)
score<-function(pred,truth){ss<-sort(unique(x$season));mean(vapply(ss,function(s){z<-x[x$season==s,];sum(z$weight*abs(pred[x$season==s]-truth[x$season==s]))/sum(z$weight)},numeric(1)))}
res<-data.frame(estimator=c('mean','median','map'),frozen_integer=NA,current_integer=NA,current_decimal=NA)
for(i in seq_len(nrow(res))){nm<-res$estimator[i];p<-x[[nm]];res$frozen_integer[i]<-score(round(p),x$peak_integer_weekF);res$current_integer[i]<-score(round(p),x$current_peak_integer);res$current_decimal[i]<-score(p,x$current_peak_decimal)}
dir.create('artifacts/m1-v2-two-pc-exploration',recursive=TRUE,showWarnings=FALSE);write.csv(x,'artifacts/m1-v2-two-pc-exploration/per_origin.csv',row.names=FALSE);write.csv(res,'artifacts/m1-v2-two-pc-exploration/summary.csv',row.names=FALSE);write.csv(meta,'artifacts/m1-v2-two-pc-exploration/library_meta.csv',row.names=FALSE)
print(res,row.names=FALSE,digits=5);cat('\nLIBRARY\n');print(meta,row.names=FALSE,digits=4)
