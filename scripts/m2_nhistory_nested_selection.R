nh_bernoulli_loss <- function(y,N,p,eps=1e-12){q<-y/N;p<-pmin(1-eps,pmax(eps,p));-(q*log(p)+(1-q)*log1p(-p))}

nh_validate_score_schema <- function(x){
  req<-c("outer_season","validation_season","horizon","spec_id","n_option","status","ordinary_loss","n_loss","row_hash","weight_hash")
  miss<-setdiff(req,names(x));if(length(miss))stop("Score schema missing: ",paste(miss,collapse=", "),call.=FALSE)
  key<-paste(x$outer_season,x$validation_season,x$horizon,x$spec_id,x$n_option,sep="\r")
  if(anyDuplicated(key))stop("Duplicate normalized score key.",call.=FALSE)
  invisible(TRUE)
}

nh_robust_guard <- function(candidate,baseline,tol=0){
  nh_validate_score_schema(candidate);nh_validate_score_schema(baseline)
  keys<-c("outer_season","validation_season","horizon")
  a<-candidate[,c(keys,"ordinary_loss","row_hash","weight_hash")];b<-baseline[,c(keys,"ordinary_loss","row_hash","weight_hash")]
  names(a)[4:6]<-c("cand_loss","cand_row","cand_weight");names(b)[4:6]<-c("base_loss","base_row","base_weight")
  z<-merge(a,b,by=keys,all=TRUE,sort=FALSE)
  if(!nrow(z)||anyNA(z))stop("Robustness guard has incomplete/empty matched seasons.",call.=FALSE)
  if(any(z$cand_row!=z$base_row|z$cand_weight!=z$base_weight))stop("Robustness guard row/weight hashes differ.",call.=FALSE)
  list(pass=all(z$cand_loss-z$base_loss<=tol),deltas=z$cand_loss-z$base_loss)
}

nh_select_n <- function(scores,n_options=nh_n_options()){
  req<-c("validation_season","n_option","n_loss","row_hash","weight_hash");miss<-setdiff(req,names(scores));if(length(miss))stop("N selector missing: ",paste(miss,collapse=", "),call.=FALSE)
  if(anyDuplicated(paste(scores$validation_season,scores$n_option,sep="\r")))stop("Duplicate season-option score.",call.=FALSE)
  options<-sort(unique(as.character(scores$n_option))); seasons<-sort(unique(as.character(scores$validation_season)))
  if(length(seasons)<2)stop("Paired one-SE selection requires >=2 validation seasons.",call.=FALSE)
  if(any(table(scores$n_option)!=length(seasons)))stop("Incomplete validation seasons across N options.",call.=FALSE)
  means<-aggregate(n_loss~n_option,scores,mean); meta<-n_options[match(means$n_option,n_options$n_option),]
  ord<-order(means$n_loss,meta$n_complexity,meta$risk_order,means$n_option); best<-as.character(means$n_option[ord[1]])
  b<-scores[scores$n_option==best,c("validation_season","n_loss","row_hash","weight_hash")];names(b)[2:4]<-c("best_loss","best_row","best_weight")
  tab<-lapply(options,function(op){a<-scores[scores$n_option==op,c("validation_season","n_loss","row_hash","weight_hash")];z<-merge(a,b,by="validation_season",sort=FALSE);if(nrow(z)!=length(seasons)||any(z$row_hash!=z$best_row|z$weight_hash!=z$best_weight))stop("Paired selector row/weight mismatch.",call.=FALSE);d<-z$n_loss-z$best_loss;data.frame(n_option=op,mean_loss=mean(z$n_loss),paired_excess=mean(d),paired_se=stats::sd(d)/sqrt(length(d)),stringsAsFactors=FALSE)})
  tab<-do.call(rbind,tab);tab$eligible<-tab$paired_excess<=tab$paired_se+1e-15;m<-n_options[match(tab$n_option,n_options$n_option),];ord<-order(!tab$eligible,m$n_complexity,m$risk_order,tab$mean_loss,tab$n_option);sel<-tab[ord[1],]
  if(!sel$eligible)stop("No option eligible under paired one-SE rule.",call.=FALSE)
  list(raw_best=best,selected=as.character(sel$n_option),table=tab)
}
