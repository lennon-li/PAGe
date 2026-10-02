source('scripts/m2_nhistory_nested_protocol.R')
source('scripts/m2_nhistory_nested_features.R')
source('scripts/m2_nhistory_nested_upstream.R')
p<-nh_protocol('m2-a-full-ntrend-v2-locked-20260930')
raw<-nh_read_flu_data(protocol=p)
cache<-'artifacts/m2-a-full-ntrend-nested-loso-v2/upstream_smoke'
ufs<-list.files(cache,full.names=TRUE,pattern='[.]rds$')
for(f in ufs){
  u<-readRDS(f); cat('\nEXCL',paste(u$excluded_seasons,collapse='|'),'\n')
  evals<-intersect(u$excluded_seasons,p$principal_seasons)
  for(s in evals){
    if(s=='2024-25')next
    z<-nh_predict_prefix(raw,u,s,24:30,c(1L,2L),p)
    if(!nrow(z)){cat(s,'NO ROWS\n');next}
    w<-z$peak_weekF_hi-z$peak_weekF_lo
    bad<-!is.finite(z$m1_p_hat)|!is.finite(z$peak_weekF_origin)|!is.finite(z$peak_weekF_lo)|!is.finite(z$peak_weekF_hi)|!is.finite(w)|w<0
    cat(s,'n=',nrow(z),' bad=',sum(bad),' zero=',sum(is.finite(w)&w==0),' neg=',sum(is.finite(w)&w<0),' NA=',sum(!is.finite(w)),'\n')
    if(any(bad)) print(z[bad,intersect(c('eval_weekF','h','m1_p_hat','peak_weekF_origin','peak_weekF_lo','peak_weekF_hi','forecast_available','unavailable_reason'),names(z))])
  }
}
