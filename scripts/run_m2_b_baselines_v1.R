ab <- read.csv('artifacts/m2-v2-flu-ab-geometry-v1/flu_ab_weekly_v1.csv', stringsAsFactors=FALSE)
ab <- ab[order(ab$season,ab$weekF),]
seasons <- sort(unique(ab$season))
out_dir <- 'artifacts/m2-v2-b-baselines-v1'
dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)

logit <- function(p) qlogis(pmin(pmax(p,1e-6),1-1e-6))
invlogit <- plogis
stab <- function(y,N,c=.5) (y+c)/(N+2*c)

# Candidate-independent ledger: all origins from week 13 with two observed
# history points and an in-season +1/+2 target. B timing is not used to create rows.
rows <- list()
for(s in seasons){
  z <- ab[ab$season==s,]
  z <- z[order(z$weekF),]
  z$p_star <- stab(z$y_B,z$N_B)
  z$logit_star <- logit(z$p_star)
  z$growth1 <- c(NA,diff(z$logit_star))
  z$growth2 <- c(NA,NA,(z$logit_star[3:nrow(z)]-z$logit_star[1:(nrow(z)-2)])/2)
  for(i in seq_len(nrow(z))){
    if(z$weekF[i] < 13 || i < 3) next
    for(h in 1:2){
      j <- i+h
      if(j>nrow(z) || z$weekF[j] != z$weekF[i]+h) next
      rows[[length(rows)+1]] <- data.frame(
        season=s,origin_week=z$weekF[i],target_week=z$weekF[j],horizon=h,
        y_target=z$y_B[j],N_target=z$N_B[j],p_target=z$p_B[j],
        y_current=z$y_B[i],N_current=z$N_B[i],p_current=z$p_B[i],p_star=z$p_star[i],
        logit_current=z$logit_star[i],growth1=z$growth1[i],growth2=z$growth2[i],
        logN=log(z$N_B[i]),denominator_regime=z$denominator_regime[i],
        stringsAsFactors=FALSE
      )
    }
  }
}
ledger <- do.call(rbind,rows);rownames(ledger)<-NULL
ledger$horizon_f <- factor(paste0('h',ledger$horizon),levels=c('h1','h2'))
write.csv(ledger,file.path(out_dir,'candidate_independent_ledger.csv'),row.names=FALSE)

preds <- list()
for(hold in seasons){
  tr <- ledger[ledger$season!=hold,]
  te <- ledger[ledger$season==hold,]
  # B0 persistence.
  te$pred_b0 <- te$p_star
  # B1 predicts logit change from current state. Offset forces current level to
  # dominate while horizon/growth/test volume estimate short-horizon drift.
  tr$offset_logit <- tr$logit_current
  te$offset_logit <- te$logit_current
  fit <- suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 +
      offset(offset_logit),
    data=tr,family=quasibinomial()
  ))
  te$pred_b1 <- as.numeric(predict(fit,newdata=te,type='response'))
  te$holdout <- hold
  preds[[hold]] <- te
}
pred <- do.call(rbind,preds);rownames(pred)<-NULL
for(nm in c('b0','b1')){
  p <- pmin(pmax(pred[[paste0('pred_',nm)]],1e-8),1-1e-8)
  pred[[paste0('err_',nm)]] <- p-pred$p_target
  pred[[paste0('abs_',nm)]] <- abs(pred[[paste0('err_',nm)]])
  pred[[paste0('sq_',nm)]] <- pred[[paste0('err_',nm)]]^2
  pred[[paste0('nll_',nm)]] <- -(pred$y_target*log(p)+(pred$N_target-pred$y_target)*log(1-p))/pred$N_target
}
write.csv(pred,file.path(out_dir,'loso_predictions.csv'),row.names=FALSE)

metric_one <- function(z,model){
  data.frame(
    n=nrow(z),
    mae_pp=100*mean(z[[paste0('abs_',model)]]),
    rmse_pp=100*sqrt(mean(z[[paste0('sq_',model)]])),
    bias_pp=100*mean(z[[paste0('err_',model)]]),
    mean_nll_per_test=mean(z[[paste0('nll_',model)]])
  )
}
per_season <- do.call(rbind,lapply(split(pred,list(pred$season,pred$horizon),drop=TRUE),function(z){
  r0<-metric_one(z,'b0');r1<-metric_one(z,'b1')
  data.frame(season=z$season[1],horizon=z$horizon[1],
             b0_mae_pp=r0$mae_pp,b1_mae_pp=r1$mae_pp,
             b0_rmse_pp=r0$rmse_pp,b1_rmse_pp=r1$rmse_pp,
             b0_bias_pp=r0$bias_pp,b1_bias_pp=r1$bias_pp,
             b0_nll=r0$mean_nll_per_test,b1_nll=r1$mean_nll_per_test,n=nrow(z))
}))
rownames(per_season)<-NULL
write.csv(per_season,file.path(out_dir,'per_season_metrics.csv'),row.names=FALSE)

summary <- do.call(rbind,lapply(1:2,function(h){
 z<-per_season[per_season$horizon==h,]
 data.frame(horizon=h,n_seasons=nrow(z),
   b0_mae_pp=mean(z$b0_mae_pp),b1_mae_pp=mean(z$b1_mae_pp),mae_improvement_pp=mean(z$b0_mae_pp-z$b1_mae_pp),
   relative_mae_improvement=1-mean(z$b1_mae_pp)/mean(z$b0_mae_pp),
   b0_rmse_pp=mean(z$b0_rmse_pp),b1_rmse_pp=mean(z$b1_rmse_pp),
   b0_nll=mean(z$b0_nll),b1_nll=mean(z$b1_nll),
   seasons_b1_better_mae=sum(z$b1_mae_pp<z$b0_mae_pp))
}))
write.csv(summary,file.path(out_dir,'summary.csv'),row.names=FALSE)
cat('B0/B1 strict LOSO season-balanced metrics\n');print(summary,row.names=FALSE,digits=5)
cat('\nPer season\n');print(per_season,row.names=FALSE,digits=4)


# Expanding-window chronological replay. Require at least 3 completed seasons
# before fitting B1; B0 remains parameter-free.
chrono_preds <- list()
for(i in seq_along(seasons)){
  hold <- seasons[i]
  train_seasons <- if(i>1) seasons[seq_len(i-1)] else character()
  if(length(train_seasons)<3) next
  tr <- ledger[ledger$season %in% train_seasons,]
  te <- ledger[ledger$season==hold,]
  tr$horizon_f <- factor(paste0('h',tr$horizon),levels=c('h1','h2'))
  te$horizon_f <- factor(paste0('h',te$horizon),levels=c('h1','h2'))
  tr$offset_logit <- tr$logit_current
  te$offset_logit <- te$logit_current
  fit <- suppressWarnings(glm(
    cbind(y_target,N_target-y_target) ~ horizon_f + growth1 + growth2 +
      offset(offset_logit), data=tr, family=quasibinomial()
  ))
  te$pred_b0 <- te$p_star
  te$pred_b1 <- as.numeric(predict(fit,newdata=te,type='response'))
  chrono_preds[[hold]] <- te
}
chrono <- do.call(rbind,chrono_preds); rownames(chrono)<-NULL
write.csv(chrono,file.path(out_dir,'chronological_predictions.csv'),row.names=FALSE)
chrono_per <- do.call(rbind,lapply(split(chrono,list(chrono$season,chrono$horizon),drop=TRUE),function(z){
  data.frame(season=z$season[1],horizon=z$horizon[1],n=nrow(z),
             b0_mae_pp=100*mean(abs(z$pred_b0-z$p_target)),
             b1_mae_pp=100*mean(abs(z$pred_b1-z$p_target)))
}))
rownames(chrono_per)<-NULL
chrono_summary <- aggregate(cbind(b0_mae_pp,b1_mae_pp)~horizon,chrono_per,mean)
chrono_summary$relative_mae_improvement <- 1-chrono_summary$b1_mae_pp/chrono_summary$b0_mae_pp
write.csv(chrono_per,file.path(out_dir,'chronological_per_season.csv'),row.names=FALSE)
write.csv(chrono_summary,file.path(out_dir,'chronological_summary.csv'),row.names=FALSE)
cat('\nChronological replay\n');print(chrono_summary,row.names=FALSE,digits=5)
