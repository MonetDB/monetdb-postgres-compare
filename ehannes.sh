#!/bin/bash
# 2014-04-04 Hannes Muehleisen <hannes@cwi.nl>

# db versions
# PostgreSQL
PGVER=9.3.4
# MonetDB
MVER=11.17.13

# protobuf stuff, does probably not need to change as fast
PBVER=2.5.0
PBCVER=0.15

DIR=/export/scratch2/hannes/compar0r/
SDIR=$DIR/.sources
IDIR=$DIR/.install

PINS=$IDIR/postgresql-$PGVER/
MINS=$IDIR/monetdb-$MVER/

PBCINS=$IDIR/protobuf-c-$PBCVER/
PBINS=$IDIR/protobuf-$PBVER/
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PBINS/lib:$PBCINS/lib

if [ ! -f $MINS/bin/mserver5 ] || [ ! -f $PINS/bin/postgres ] || [ ! -f $PINS/lib/cstore_fdw.so ] ; then
	mkdir -p $SDIR
	mkdir -p $IDIR

	# download sources
	PGURL=http://ftp.postgresql.org/pub/source/v$PGVER/postgresql-$PGVER.tar.gz
	MURL=http://www.monetdb.org/downloads/sources/Latest/MonetDB-$MVER.tar.bz2

	rm -rf $SDIR/*

	wget $PGURL -P $SDIR
	wget $MURL -P $SDIR --no-check-certificate
	git clone https://github.com/citusdata/cstore_fdw/ $SDIR/cstore_fdw

	# download, unpack and install protobuf & protobuf-c, needed for cstore_fdw
	wget https://protobuf.googlecode.com/files/protobuf-$PBVER.tar.gz -P $SDIR
	wget https://protobuf-c.googlecode.com/files/protobuf-c-$PBCVER.tar.gz -P $SDIR
	wget http://www.tpc.org/tpch/spec/tpch_2_16_1.zip -P $SDIR

	rm -rf $IDIR/*

	# unpack everything
	for i in $SDIR/*.tar.*; do tar xvf $i -C $SDIR; done
	unzip $SDIR/tpch_*.zip -d $SDIR

	# make TPCH dbgen
	cd $SDIR/tpch_2_16_1/dbgen
	sed -e 's/DATABASE\s*=/DATABASE=DB2/' -e 's/MACHINE\s*=/MACHINE=LINUX/' -e 's/WORKLOAD\s*=/WORKLOAD=TPCH/' -e 's/CC\s*=/CC=gcc/' makefile.suite > Makefile
	make
	mkdir $IDIR/dbgen/
	cp dbgen dists.dss $IDIR/dbgen/

	# okay, now compile everything
	PSRC=$SDIR/postgresql-$PGVER/
	cd $PSRC
	./configure --prefix=$PINS
	make
	make install

	MSRC=$SDIR/MonetDB-$MVER/
	cd $MSRC
	./configure --prefix=$MINS --enable-rubygem=no --enable-python3=no --enable-python2=no --enable-perl=no --enable-geos=no --enable-python=no --enable-geom=no --enable-fits=no --enable-jaql=no --enable-gsl=no --enable-odbc=no --enable-jdbc=no --enable-merocontrol=no
	make -j install

	# protobuf and protbuf-c are dependencies of cstore
	PBSRC=$SDIR/protobuf-$PBVER/
	cd $PBSRC
	./configure --prefix=$PBINS
	make -j install

	PBCSRC=$SDIR/protobuf-c-$PBCVER/
	cd $PBCSRC
	./configure --prefix=$PBCINS CXXFLAGS=-I$IDIR/protobuf-$PBVER/include LDFLAGS=-L$IDIR/protobuf-$PBVER/lib PATH=$PATH:$PBINS/bin/
	make -j install

	# cstore is a pgplugin, therefore it has to be built last
	CSRC=$SDIR/cstore_fdw
	cd $CSRC
	PATH=$PATH:$PINS/bin/:$PBCINS/bin/ CPATH=$CPATH:$PBCINS/include LIBRARY_PATH=$LIBRARY_PATH:$PBCINS/lib make -j install

	# this should be it, check for certain files

	rm -rf $SDIR/*
fi


# some sys setup for PostgreSQL according to Dr. Kyzirakos

### RAM
## 4 GB of RAM
#shared_buffers       =  3GB
#effective_cache_size =  3GB
#maintenance_work_mem =  1GB
#work_mem             =  2GB
## 8 GB of RAM
#shared_buffers       =  5GB
#effective_cache_size =  6GB
#maintenance_work_mem =  2GB
#work_mem             =  5GB
## 16 GB of RAM
#shared_buffers       = 10GB
#effective_cache_size = 14GB
#maintenance_work_mem =  4GB
#work_mem             = 10GB
## 24 GB of RAM
#shared_buffers       = 16GB
#effective_cache_size = 22GB
#maintenance_work_mem =  6GB
#work_mem             = 15GB
## 48 GB of RAM
#shared_buffers       = 32GB
#effective_cache_size = 46GB
#maintenance_work_mem =  8GB
#work_mem             = 30GB

## 4 GB of RAM
#kernel.shmmax = 3758096384
#kernel.shmall = 3758096384
#kernel.shmmni = 4096
## 8 GB of RAM
#kernel.shmmax = 5905580032
#kernel.shmall = 5905580032
#kernel.shmmni = 4096
## 16 GB of RAM
#kernel.shmmax = 11274289152
#kernel.shmall = 11274289152
#kernel.shmmni = 4096
## 24 GB of RAM
#kernel.shmmax = 17716740096
#kernel.shmall = 17716740096
#kernel.shmmni = 4096
## 48 GB of RAM
#kernel.shmmax = 35433480192
#kernel.shmall = 35433480192
#kernel.shmmni = 4224
## 64 GB of RAM

# here: 16 GB
pg_shared_buffers=10GB
pg_effective_cache_size=6GB
pg_work_mem=5GB

#sudo bash -c "sysctl -w kernel.shmmax=11274289152"
#sudo bash -c "sysctl -w kernel.shmall=11274289152"
#sudo bash -c "sysctl -w kernel.shmmni=4096"

# okay, run tpc-h

DDIR=$DIR/.data
SCDIR=$DIR/scripts
QYDIR=$DIR/queries
QRDIR=$DIR/.querylogs

RESFL=$DIR/results.tsv

touch $RESFL;

FARM=$DIR/.farms

PORT=51337
mkdir -p $DDIR
mkdir -p $FARM
mkdir -p $QRDIR

TIMINGCMD="/usr/bin/time -o $DIR/.time -f %e"

for SF in 1 # 10 30
do
	# check if we have data
	SFDDIR=$DDIR/sf-$SF/
	# if not, generate
	if [ ! -f $SFDDIR/lineitem.tbl ] ; then
		cd $IDIR/dbgen/
		./dbgen -vf -s $SF
		mkdir -p $SFDDIR
		# clean up stupid line endings
		for i in *.tbl; do sed -i 's/.$//' $i ; done
		mv *.tbl $SFDDIR
	fi
	cd $DIR
	for DB in citusdata postgres monetdb
	do
		DBNAME=$DB-sf$SF
		DBFARM=$FARM/$DBNAME/
		#rm -rf $DBFARM/*

		if [ "$DB" == "monetdb" ]; then
			SERVERCMD="$MINS/bin/mserver5 --set mapi_port=$PORT --daemon=yes --dbpath="
			CLIENTCMD="$MINS/bin/mclient -p $PORT "
			INITFCMD="echo "
		fi
		if [ "$DB" == "postgres" ] || [ "$DB" == "citusdata" ]; then
			SERVERCMD="$PINS/bin/postgres -p $PORT \
			-c autovacuum=off \
			-c random_page_cost=3.5 \
			-c geqo_threshold=15 \
			-c from_collapse_limit=14 \
			-c join_collapse_limit=14 \
			-c default_statistics_target=10000 \
			-c constraint_exclusion=on \
			-c checkpoint_completion_target=0.9 \
			-c wal_buffers=32MB \
			-c checkpoint_segments=64 \
			-c max_connections=10 \
			-c shared_preload_libraries=cstore_fdw \
			 -D "
			CLIENTCMD="$PINS/bin/psql -p $PORT tpch -t -A -F , -f " 
			INITFCMD="$PINS/bin/initdb -D "
			CREATEDBCMD="$PINS/bin/createdb -p $PORT tpch"

		fi
		if [ ! -d $DBFARM ] ; then
			# clear caches (fair loading)
			#sudo bash -c "echo 3 > /proc/sys/vm/drop_caches"
			mkdir -p $DBFARM

			# initialize db directory
			$INITFCMD$DBFARM

			# start db server
			$SERVERCMD$DBFARM > /dev/null &
			sleep 5
			
			# create db (if applicable)
			$CREATEDBCMD
			
			# create schema
			sed -e "s|DIR|$DBFARM|" $SCDIR/$DB.schema.sql > $DIR/.$DB.schema.sql.local
			$CLIENTCMD $DIR/.$DB.schema.sql.local > /dev/null

			# load data
			sed -e "s|DIR|$SFDDIR|" $SCDIR/$DB.load.sql > $DIR/.$DB.load.sql.local
			$TIMINGCMD $CLIENTCMD $DIR/.$DB.load.sql.local > /dev/null
			LDTIME=`cat $DIR/.time`
			echo -e "$DB\t$SF\tload\t\t$LDTIME" >> $RESFL

			# constraints
			$TIMINGCMD $CLIENTCMD $SCDIR/$DB.constraints.sql > /dev/null
			CTTIME=`cat $DIR/.time`
			echo -e "$DB\t$SF\tconstraints\t\t$CTTIME" >> $RESFL

			# analyze/vacuum
			$TIMINGCMD $CLIENTCMD $SCDIR/$DB.analyze.sql > /dev/null
			AZTIME=`cat $DIR/.time`
			echo -e "$DB\t$SF\tanalyze\t\t$AZTIME" >> $RESFL
			
			# aand restart
			kill `jobs -p`
			sleep 10
		fi
		# we start with cold runs
		# clear caches (fair loading)
		for coldrun in {1..2}
		do
			for i in $QYDIR/q??.sql
			do
				#sudo bash -c "echo 3 > /proc/sys/vm/drop_caches"
				$SERVERCMD$DBFARM > /dev/null &
				sleep 5
				q=${i%.sql}
				qn=`basename $q`
				$TIMINGCMD $CLIENTCMD $i > $QRDIR/$DB-SF$SF-coldrun$coldrun-q$qn.out
				QTIME=`cat $DIR/.time`
				echo -e "$DB\t$SF\tcoldruns\t$qn\t$QTIME" >> $RESFL
				kill `jobs -p`
				sleep 10
			done
			
		done

		# warmup...
		$SERVERCMD$DBFARM > /dev/null &
		sleep 5
		for warmup in {1..3}
		do
			for i in $QYDIR/q??.sql
			do
				q=${i%.sql}
				qn=`basename $q`
				$TIMINGCMD $CLIENTCMD $i > $QRDIR/$DB-SF$SF-warmup$warmup-q$qn.out
				QTIME=`cat $DIR/.time`
				echo -e "$DB\t$SF\twarmup\t$qn\t$QTIME" >> $RESFL
			done
		done

		# hot runs!
		for hotrun in {1..5}
		do
			for i in $QYDIR/q??.sql
			do
				q=${i%.sql}
				qn=`basename $q`
				$TIMINGCMD $CLIENTCMD $i $QRDIR/$DB-SF$SF-hotrun$hotrun-q$qn.out
				QTIME=`cat $DIR/.time`
				echo -e "$DB\t$SF\thotruns\t$qn\t$QTIME" >> $RESFL
			done
		done
		kill `jobs -p`
		sleep 10
	done

done

rm $DIR/.*.sql.local
rm $DIR/.time