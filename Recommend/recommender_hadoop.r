Sys.setenv(HADOOP_CMD="/usr/bin/hadoop")
Sys.setenv(HADOOP_STREAMING="/usr/lib/hadoop-mapreduce/hadoop-streaming.jar")
args<-commandArgs(TRUE)
library(stringr)
library (rmr2)
library (rhdfs)
hdfs.init()
rmr.options(backend="local")

hdfs.content = hdfs.read.text.file(args[1])
train = as.data.frame(str_split_fixed(as.data.frame(hdfs.content)[,1], ",", 3))
names (train) <-c ("user", "item", "pref")
train$user = as.integer(train$user)
train$item = as.integer(train$item)
train$pref = as.numeric(train$pref)

train.hdfs = to.dfs (keyval (train$user, train))
#from.dfs (train.hdfs)

train.mr<-mapreduce(
  input=train.hdfs, 
  map = function(k, v) {
    keyval(k,v$item)
  }
  ,reduce=function(k,v){
    m<-merge(v,v)
    keyval(m$x,m$y)
  }
)
library(plyr)
#from.dfs(train.mr)
step2.mr<-mapreduce(
  train.mr,
  map = function(k, v) {
    d<-data.frame(k,v)
    d2<-ddply(d,.(k,v),count)
    
    key<-d2$k
    val<-d2
    keyval(key,val)
  }
)
#from.dfs(step2.mr)

train2.mr<-mapreduce(
  train.hdfs, 
  map = function(k, v) {
    df<-v
    key<-df$item
    val<-data.frame(item=df$item,user=df$user,pref=df$pref)
    keyval(key,val)
  }
)
#from.dfs(train2.mr)

eq.hdfs<-equijoin(
  left.input=step2.mr, 
  right.input=train2.mr,
  map.left=function(k,v){
    keyval(k,v)
  },
  map.right=function(k,v){
    keyval(k,v)
  },
  outer = c("left")
)
#from.dfs(eq.hdfs)


cal.mr<-mapreduce(
  input=eq.hdfs,
  map=function(k,v){
    val<-v
    na<-is.na(v$user.r)
    if(length(which(na))>0) val<-v[-which(is.na(v$user.r)),]
    keyval(val$k.l,val)
  }
  ,reduce=function(k,v){
    val<-ddply(v,.(k.l,v.l,user.r),summarize,v=freq.l*pref.r)
    keyval(val$k.l,val)
  }
)
#from.dfs(cal.mr)
csv.format = make.output.format("csv", quote=FALSE, sep = "\t")
result.mr<-mapreduce(
  input=cal.mr,
  output=args[2],
  output.format = csv.format,
  map=function(k,v){
    keyval(v$user.r,v)
  }
  ,reduce=function(k,v){
    val<-ddply(v,.(user.r,v.l),summarize,v=sum(v))
    val2<-val[order(val$v,decreasing=TRUE),]
    names(val2)<-c("user","item","pref")
     a = paste('[', paste(100+val2$item, collapse=',' ), ']', collpase='')
    keyval(unique(val2$user),a)
  }
)

#from.dfs(result.mr)
