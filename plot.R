library(ggplot2)
library(ggthemes)
library(scales)
library(plyr)

#setwd("~/Desktop/compare/")
setwd("~/git/monetdb-postgres-compare/results/results-2014-04-07")

textsize <- 16
theme <- theme_few(base_size = textsize) + 
theme(axis.text.x = element_text(angle = 90, hjust = 1),
	  legend.title=element_blank(),
	  legend.position=c(0.85,0.08))

compare <- read.table("results.tsv",sep="\t",na.strings="")
names(compare) <- c ("db","dbver","bmark","sf","phase","q","rep","time")

#compare.old <- read.table("results-hot-oldformat.tsv",sep="\t",na.strings="")
#names(compare.old) <- c ("db","sf","phase","q","time")

#compare.old <- compare.old[compare.old$phase=="hotruns",]
#compare.old$rep <- 0
#compare.old$dbver <- "42"
#compare.old$bmark <- "tpch"

#compare <- rbind(compare,compare.old)

# we have a 30 min time limit, so everything over that is a fail
#compare[compare$time>1800,]$time <- NA

levels(compare$db) <- c("Citusdata","MonetDB","PostgreSQL")
compare$db <- ordered(compare$db,levels=c("PostgreSQL","Citusdata","MonetDB"))
levels(compare$q) <- toupper(levels(compare$q))

tpcplot <- function(data,filename="out.pdf",sf=1,phase="hotruns",queries=levels(data$q),width=8,ylimit=100,main="",sub="") {
  pdata <- ddply(data[which(data$sf == as.character(sf) & data$phase==as.character(phase)),], 
                 c("db", "q"), summarise, avgtime = mean(time),
                 se = sd(time) / sqrt(length(time)) )  
  pdata <- pdata[pdata$q %in% queries,]  
  if (nrow(pdata) < 1) {warning("No data, dude."); return(NA)}
  pdata$outlier <- pdata$avgtime > ylimit
  if (nrow(pdata[pdata$outlier,]) > 0) pdata[pdata$outlier,]$se <- NA
  pdf(filename,width=width,height=6)
  dodge <- position_dodge(width=.8)
  print(ggplot(pdata,aes(x=q,y=avgtime,fill=db)) + 
    geom_bar(width=.65,position = dodge,stat="identity") + scale_y_continuous(limits = c(0, ylimit),oob=squish) + 
    geom_errorbar(aes(ymin=avgtime-se, ymax=avgtime+se), width=0.07,position=dodge) +
    ggtitle(bquote(atop(.(main), atop(.(sub), "")))) + xlab("") + ylab("Duration (seconds)") + 
    scale_fill_manual(values = c("PostgreSQL" = "#2f7ed8", "Citusdata" = "#AA4643","MonetDB" = "#568203")) + 
    theme_few(base_size = textsize) + theme(legend.position="bottom", legend.title=element_blank(), panel.border = element_blank(),axis.line = element_line(colour = "black")) +
    geom_text(aes(label=ifelse(outlier, paste0("^ ",round(avgtime),"s"), ""), hjust=.5,vjust=-.2), position = dodge))
  dev.off()
}


qss <- c("Q03","Q05","Q06","Q10")

# sf1
tpcplot(data=compare,filename="sf1-hot-subset.pdf",sf="1",phase="hotruns",queries=qss,ylimit=4,main="Query Speed (Hot)",sub="TPC-H SF1 (1.1 GB)")
tpcplot(data=compare,filename="sf1-hot-all.pdf",sf="1",phase="hotruns",ylimit=25,main="Query Speed (Hot)",sub="TPC-H SF1 (1.1 GB)",width=20)
tpcplot(data=compare,filename="sf1-cold-subset.pdf",sf="1",phase="coldruns",queries=qss,ylimit=12,main="Query Speed (Cold)",sub="TPC-H SF1 (1.1 GB)")
tpcplot(data=compare,filename="sf1-cold-all.pdf",sf="1",phase="coldruns",ylimit=25,main="Query Speed (Cold)",sub="TPC-H SF1 (1.1 GB)",width=20)

# sf5
tpcplot(data=compare,filename="sf5-hot-subset.pdf",sf="5",phase="hotruns",queries=qss,ylimit=70,main="Query Speed (Hot)",sub="TPC-H SF5 (5.2 GB)")
tpcplot(data=compare,filename="sf5-hot-all.pdf",sf="5",phase="hotruns",ylimit=80,main="Query Speed (Hot)",sub="TPC-H SF5 (5.2 GB)",width=20)
tpcplot(data=compare,filename="sf5-cold-subset.pdf",sf="5",phase="coldruns",queries=qss,ylimit=70,main="Query Speed (Cold)",sub="TPC-H SF5 (5.2 GB)")
tpcplot(data=compare,filename="sf5-cold-all.pdf",sf="5",phase="coldruns",ylimit=100,main="Query Speed (Cold)",sub="TPC-H SF5 (5.2 GB)",width=20)

# sf10
tpcplot(data=compare,filename="sf10-hot-subset.pdf",sf="10",phase="hotruns",queries=qss,ylimit=40,main="Query Speed (Hot)",sub="TPC-H SF10 (11 GB)")
tpcplot(data=compare,filename="sf10-hot-all.pdf",sf="10",phase="hotruns",ylimit=100,main="Query Speed (Hot)",sub="TPC-H SF10 (11 GB)",width=20)
tpcplot(data=compare,filename="sf10-cold-subset.pdf",sf="10",phase="coldruns",queries=qss,ylimit=70,main="Query Speed (Cold)",sub="TPC-H SF10 (11 GB)")
tpcplot(data=compare,filename="sf10-cold-all.pdf",sf="10",phase="coldruns",ylimit=100,main="Query Speed (Cold)",sub="TPC-H SF10 (11 GB)",width=20)
