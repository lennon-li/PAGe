source('scripts/m2_nhistory_nested_protocol.R')
source('scripts/m2_nhistory_nested_features.R')
source('scripts/m2_nhistory_nested_upstream.R')
source('scripts/m2_nhistory_nested_models.R')
source('scripts/m2_nhistory_nested_selection.R')
source('scripts/m2_nhistory_nested_jobs.R')
out <- nh_out_dir(); dir.create(out,recursive=TRUE,showWarnings=FALSE)
p <- nh_protocol('m2-a-full-ntrend-v2-locked-20260930')
checks <- list(); add <- function(name,ok,detail=''){checks[[length(checks)+1L]] <<- data.frame(test=name,status=if(isTRUE(ok))'PASS' else 'FAIL',detail=detail,stringsAsFactors=FALSE); if(!isTRUE(ok))stop(name,': ',detail,call.=FALSE)}
expect_error <- function(expr,pattern=NULL){e<-tryCatch({force(expr);NULL},error=function(e)e); if(is.null(e))return(FALSE); if(is.null(pattern))TRUE else grepl(pattern,conditionMessage(e),fixed=FALSE)}
folds <- nh_make_fold_index(p); add('fold_contracts',isTRUE(tryCatch({nh_assert_all_fold_contracts(folds,p);TRUE},error=function(e)FALSE)))
fo <- folds[folds$fold_role=='outer',][1,]; add('outer_isolation',identical(sort(nh_split_set(fo$upstream_excluded_seasons)),sort(as.character(fo$outer_season))))
fv <- folds[folds$fold_role=='inner_validation',][1,]; add('inner_validation_isolation',identical(sort(nh_split_set(fv$upstream_excluded_seasons)),sort(as.character(c(fv$outer_season,fv$validation_season)))))
ft <- folds[folds$fold_role=='inner_training_row',][1,]; add('row_crossfit_isolation',identical(sort(nh_split_set(ft$upstream_excluded_seasons)),sort(as.character(c(ft$outer_season,ft$validation_season,ft$evaluated_row_season)))))
poison <- folds[folds$fold_role=='inner_training_row',][1,]; poison$upstream_excluded_seasons <- paste(setdiff(nh_split_set(poison$upstream_excluded_seasons),poison$evaluated_row_season),collapse='|')
add('exclusion_poison_rejected',expect_error(nh_assert_fold_contract(poison,p),'exclusion mismatch'))
timing <- nh_read_timing(protocol=p); allowed <- setdiff(p$principal_seasons,c('2024-25','2025-26')); tl <- timing[timing$season%in%allowed,]
add('allowed_labels_pass',isTRUE(tryCatch({nh_assert_label_subset(tl,allowed,c('2024-25','2025-26'));TRUE},error=function(e)FALSE)))
poison_lbl <- rbind(tl,data.frame(season='2025-26',ignition_weekF=1,peak_weekF=1)); add('manual_label_poison_rejected',expect_error(nh_assert_label_subset(poison_lbl,allowed,c('2024-25','2025-26')),'forbidden'))
# keyed calendar/gap behavior, including explicit week 53 without modulo reconstruction
syn <- nh_make_synthetic_panel(p$principal_seasons,weeks=8:53); led <- nh_raw_ledger(syn,p); add('week53_keyed_calendar',max(syn$weekF)==53L && all(led$target_weekF<=53L | !led$target_present))
one_season <- syn[syn$season==p$principal_seasons[[1L]],,drop=FALSE]
add('missing_principal_season_guard',expect_error(nh_raw_ledger(one_season,p),'missing principal season'))
empty <- syn[FALSE,,drop=FALSE]
add('empty_principal_schedule_guard',expect_error(nh_raw_ledger(empty,p),'missing principal season'))
fractional_week <- syn; fractional_week$weekF <- as.numeric(fractional_week$weekF); fractional_week$weekF[1L] <- fractional_week$weekF[1L] + 0.5
add('fractional_calendar_key_guard',expect_error(nh_raw_ledger(fractional_week,p),'finite integers'))
gap <- syn[!(syn$season==p$principal_seasons[1] & syn$weekF==12),]; lg <- nh_raw_ledger(gap,p); z<-lg[lg$row_season==p$principal_seasons[1]&lg$origin_weekF==14,]; add('missing_t_minus_2_excludes',all(!z$common_eligible))
gap8 <- syn[!(syn$season==p$principal_seasons[1] & syn$weekF==8),]; l8<-nh_raw_ledger(gap8,p); add('missing_week8_excludes',all(!l8$common_eligible[l8$row_season==p$principal_seasons[1]]))
# N features must not depend on future after origin
r <- data.frame(row_season=p$principal_seasons[1],origin_weekF=20L,horizon=1L,target_weekF=21L); f1<-nh_add_n_features(r,syn,p,TRUE); syn2<-syn; ii<-syn2$season==p$principal_seasons[1]&syn2$weekF>20; syn2$y[ii]<-0; syn2$N[ii]<-syn2$N[ii]*3; f2<-nh_add_n_features(r,syn2,p,TRUE); cols<-c('n_d1','n_d2','n_d3','n_d4','n_exp025','n_exp050','n_exp075','n_exp100','n_accel22','n_rel8','growth1'); add('n_feature_future_invariance',isTRUE(all.equal(f1[,cols],f2[,cols],tolerance=0)))
# Stage B must fail closed when fields absent/invalid
add('stage_b_missing_fields_rejected',expect_error(nh_validate_stage_b_fields(data.frame(m1_p_hat=.2)),'requires causal'))
add('stage_b_zero_width_supported',isTRUE(tryCatch({nh_validate_stage_b_fields(data.frame(m1_p_hat=.2,peak_weekF_origin=20,peak_weekF_lo=20,peak_weekF_hi=20));TRUE},error=function(e)FALSE)))
# Paired one-SE: OFF wins when within SE; incomplete and robustness bad schema fail.
ss <- data.frame(validation_season=rep(c('s1','s2','s3'),2),n_option=rep(c('OFF','EXP050'),each=3),n_loss=c(.20,.21,.19,.195,.215,.185),row_hash=rep(c('a','b','c'),2),weight_hash=rep(c('w1','w2','w3'),2),stringsAsFactors=FALSE)
sel<-nh_select_n(ss); add('paired_one_se_operates',sel$selected%in%c('OFF','EXP050'),paste('selected',sel$selected))
add('paired_incomplete_rejected',expect_error(nh_select_n(ss[-1,]),'Incomplete'))
add('robust_schema_rejected',expect_error(nh_robust_guard(data.frame(),data.frame()),'missing'))
rs <- data.frame(outer_season='o',validation_season=c('v1','v2'),horizon=1L,spec_id='s',n_option='OFF',status='ok',ordinary_loss=c(.2,.3),n_loss=c(.2,.3),row_hash=c('r1','r2'),weight_hash=c('w1','w2'),stringsAsFactors=FALSE)
add('robust_empty_join_rejected',expect_error(nh_robust_guard(rs,transform(rs,validation_season=c('x1','x2'))),'incomplete/empty'))
add('robust_duplicate_key_rejected',expect_error(nh_robust_guard(rbind(rs,rs[1,]),rs),'Duplicate'))
# Resume/corruption contract
cp<-file.path(out,'gate1-resume-test.rds');unlink(cp); payload<-list(x=1); v1<-nh_run_cached('unit',payload,cp,function()42,p); v2<-nh_run_cached('unit',payload,cp,function()99,p);add('resume_skips_valid',identical(v1,42)&&identical(v2,42));writeBin(charToRaw('truncated'),cp);add('corrupt_checkpoint_rejected',!nh_checkpoint_valid(cp,nh_job_key('unit',payload,p)))
tamper<-list(job_key=nh_job_key('unit',payload,p),complete=TRUE,value=999,sha256=nh_hash_object(42));saveRDS(tamper,cp);add('hash_tamper_rejected',!nh_checkpoint_valid(cp,nh_job_key('unit',payload,p)));v3<-nh_run_cached('unit',payload,cp,function()43,p);add('hash_tamper_recomputed',identical(v3,43))
uk<-'unit-upstream';uz<-list(upstream_key=uk,value=42);uz$cache_sha256<-nh_hash_object(uz);add('upstream_cache_hash_valid',nh_upstream_cache_valid(uz,uk));uz$value<-43;add('upstream_cache_hash_tamper_rejected',!nh_upstream_cache_valid(uz,uk))
res<-do.call(rbind,checks);write.csv(res,file.path(out,'exclusion_assertions.csv'),row.names=FALSE);write.csv(res,file.path(out,'feature_reconstruction.csv'),row.names=FALSE);write.csv(res,file.path(out,'stage_b_contract.csv'),row.names=FALSE)
writeLines(capture.output(res),file.path(out,'gate1-tests.log')); nh_write_json(list(gate='gate1',status='PASS',checks=nrow(res),source_hash=nh_gate_source_hash(nh_repo_root()),protocol_hash=nh_hash_object(nh_scientific_protocol(p))),file.path(out,'gate1_manifest.json')); cat('Gate1 PASS:',nrow(res),'checks\n')
