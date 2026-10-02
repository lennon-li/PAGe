nh_job_key <- function(layer,payload,protocol=nh_protocol()) digest::digest(list(layer=layer,payload=payload,protocol=protocol),algo="sha256")
nh_atomic_save_rds <- function(x,path){dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE);tmp<-paste0(path,".tmp-",Sys.getpid());saveRDS(x,tmp);if(!file.rename(tmp,path))stop("Atomic rename failed.",call.=FALSE);invisible(path)}
nh_checkpoint_valid <- function(path,key){if(!file.exists(path))return(FALSE);x<-tryCatch(readRDS(path),error=function(e)NULL);is.list(x)&&identical(x$job_key,key)&&isTRUE(x$complete)&&is.character(x$sha256)&&length(x$sha256)==1L&&identical(x$sha256,nh_hash_object(x$value))}
nh_run_cached <- function(layer,payload,path,fun,protocol=nh_protocol()){
  key<-nh_job_key(layer,payload,protocol);if(nh_checkpoint_valid(path,key))return(readRDS(path)$value)
  value<-fun();nh_atomic_save_rds(list(job_key=key,complete=TRUE,value=value,sha256=nh_hash_object(value)),path);value
}
