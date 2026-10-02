#!/usr/bin/env Rscript

ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv', stringsAsFactors=FALSE)
ledger <- read.csv('artifacts/m2-v2-b-baselines-v1/candidate_independent_ledger.csv', stringsAsFactors=FALSE)
seasons <- sort(unique(ledger$season))
out_dir <- 'artifacts/m2-v2-b-baseline-nested-fallback-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

# Causal trailing activity summaries.
stats_rows <- list()
for(s in seasons){
  z<-ab[ab$season==s,];z<-z[order(z$weekF),]
  sum4<-as.numeric(stats::filter(z$y_B,rep(1,4),sides=1))
  maxp4<-vapply(seq_len(nrow(z)),function(i)max(z$p_B[max(1,i-3):i],na.rm=TRUE),numeric(1))
  stats_rows[[s]]<-data.frame(season=s,origin_week=z$weekF,sum4=sum4,maxp4=maxp4)
}
act<-do.call(rbind,stats_rows)
ledger<-merge(ledger,act,by=c('season','origin_week'),all.x=TRUE,sort=FALSE)
ledger$horizon_f<-factor(paste0('h',ledger$horizon),levels=c('h1','h2'))

fit_b1 <- function(tr){
  tr$horizon_f<-factor(paste0('h',tr$horizon),levels=c('h1','h2'))
  tr$offset_logit<-tr$logit_current
  suppressWarnings(glm(cbind(y_target,N_target-y_target)~horizon_f+growth1+growth2+offset(offset_logit),data=tr,family=quasibinomial()))
}

# Candidate controls when to trust growth. 'all' is current B1; 'none' is B0.
cands<-rbind(
  data.frame(candidate='none',p_thr=Inf,count_thr=Inf),
  data.frame(candidate='all',p_thr=-Inf,count_thr=-Inf),
  do.call(rbind,lapply(c(.005,.01,.02,.03),function(p)do.call(rbind,lapply(c(5,10,20,40),function(n)data.frame(candidate=paste0('p',sprintf('%03d',round(1000*p)),'_n',n),p_thr=p,count_thr=n)))))
)
apply_cand<-function(z,p0,p1,cnd){
 if(cnd$candidate=='none') return(p0)
 if(cnd$candidate=='all') return(p1)
 active<-is.finite(z$sum4)&z$sum4>=cnd$count_thr&is.finite(z$maxp4)&z$maxp4>=cnd$p_thr
 ifelse(active,p1,p0)
}

preds<-list();sels<-list();inner_all<-list()
for(outer in seasons){
 train_outer<-setdiff(seasons,outer)
 for(h in 1:2){
  scores<-numeric(nrow(cands))
  for(ci in seq_len(nrow(cands))){
   cnd<-cands[ci,];errs<-numeric()
   for(v in train_outer){
    tr<-ledger[ledger$season%in%setdiff(train_outer,v),];va<-ledger[ledger$season==v&ledger$horizon==h,]
    fit<-fit_b1(tr);va$offset_logit<-va$logit_current;p1<-as.numeric(predict(fit,newdata=va,type='response'));p0<-va$p_star
    pv<-apply_cand(va,p0,p1,cnd);errs<-c(errs,100*mean(abs(pv-va$p_target)))
   }
   scores[ci]<-mean(errs);inner_all[[paste(outer,h,ci)]]<-data.frame(outer=outer,horizon=h,candidate=cnd$candidate,inner_mae_pp=scores[ci])
  }
  best<-which(scores==min(scores))[1];cnd<-cands[best,]
  sels[[paste(outer,h)]]<-data.frame(outer=outer,horizon=h,candidate=cnd$candidate,p_thr=cnd$p_thr,count_thr=cnd$count_thr,inner_mae_pp=scores[best])
 }
 tr<-ledger[ledger$season%in%train_outer,];te<-ledger[ledger$season==outer,];fit<-fit_b1(tr);te$offset_logit<-te$logit_current;te$pred_b0<-te$p_star;te$pred_b1<-as.numeric(predict(fit,newdata=te,type='response'));te$pred_selected<-te$pred_b1
 for(h in 1:2){sel<-sels[[paste(outer,h)]];cnd<-cands[cands$candidate==sel$candidate,][1,];ix<-which(te$horizon==h);te$pred_selected[ix]<-apply_cand(te[ix,],te$pred_b0[ix],te$pred_b1[ix],cnd);te$selected_candidate[ix]<-sel$candidate}
 preds[[outer]]<-te
}
pred<-do.call(rbind,preds);sel<-do.call(rbind,sels);inner<-do.call(rbind,inner_all)
write.csv(pred,file.path(out_dir,'outer_predictions.csv'),row.names=FALSE);write.csv(sel,file.path(out_dir,'outer_selections.csv'),row.names=FALSE);write.csv(inner,file.path(out_dir,'inner_scores.csv'),row.names=FALSE)
for(m in c('b0','b1','selected')){p<-pmin(pmax(pred[[paste0('pred_',m)]],1e-8),1-1e-8);pred[[paste0('abs_',m)]]<-abs(p-pred$p_target);pred[[paste0('nll_',m)]]<--(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target}
per<-do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z)data.frame(season=z$season[1],horizon=z$horizon[1],candidate=z$selected_candidate[1],b0_mae_pp=100*mean(z$abs_b0),b1_mae_pp=100*mean(z$abs_b1),selected_mae_pp=100*mean(z$abs_selected),b1_nll=mean(z$nll_b1),selected_nll=mean(z$nll_selected),n=nrow(z))))
write.csv(per,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)
summary<-do.call(rbind,lapply(split(per,per$horizon),function(z)data.frame(horizon=z$horizon[1],b0_mae_pp=mean(z$b0_mae_pp),b1_mae_pp=mean(z$b1_mae_pp),selected_mae_pp=mean(z$selected_mae_pp),selected_vs_b1_gain=1-mean(z$selected_mae_pp)/mean(z$b1_mae_pp),b1_nll=mean(z$b1_nll),selected_nll=mean(z$selected_nll),seasons_better=sum(z$selected_mae_pp<z$b1_mae_pp),seasons_worse=sum(z$selected_mae_pp>z$b1_mae_pp))))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('Selections\n');print(sel,row.names=FALSE,digits=4);cat('\nSummary\n');print(summary,row.names=FALSE,digits=5);cat('\nPer season\n');print(per,row.names=FALSE,digits=4)
