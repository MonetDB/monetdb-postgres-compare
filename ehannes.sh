
#!/bin/bash
#set -x

# command line parameter parsing fun
usage() { echo "Usage: $0 -s <scale factors> -d <databases to test> -p <directory prefix>" 1>&2; exit 1; }

while getopts ":s:d:p:" o; do
    case "${o}" in
        s)
            s=${OPTARG}
            ;;
        d)
            d=${OPTARG}
            ;;
        p)
            p=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${p}" ] ; then
    echo "-p is required. Example: -p /tmp/ehannes/" 1>&2;
    usage
fi

mkdir -p $p
if [ ! -d "${p}" ] ; then
    echo "Directory $p does not exist and cannot be created." 1>&2;
    usage
fi

if [ -z "${s}" ] ; then
    echo "-s is required. Example: -s \"1 3 10\"" 1>&2;
    usage
fi
for SF in $s
do
    if [ $SF -lt 1 ] ; then
        echo "Invalid value for scale factor: $SF" 1>&2;
        exit 1
    fi
done

if [ -z "${d}" ] ; then
    echo "-d is required. Example: -d \"monetdb postgres\"" 1>&2;
    usage
fi

for DB in $d
do
    echo $DB | grep "monetdb\|postgres\|mariadb\|citusdb" > /dev/null
    if [ ! $? -eq 0 ] ; then
        echo "Invalid value for database: $DB" 1>&2;
        exit 1
    fi
done

echo "TPC-H DB comparision script, <hannes@cwi.nl> 2014"
echo
echo "Testing databases $d"
echo "Testing scale factors $s"
echo "Using prefix directory $p"



# db versions
# PostgreSQL
PGVER=9.3.4
# MonetDB
MVER=11.17.13
# MariaDB
MAVER=10.0.10

# protobuf stuff, does probably not need to change as fast
PBVER=2.5.0
PBCVER=0.15

DIR=$p
SDIR=$DIR/.sources
IDIR=$DIR/.install

PINS=$IDIR/postgresql-$PGVER/
MINS=$IDIR/monetdb-$MVER/
MAINS=$IDIR/mariadb-$MAVER/

PBCINS=$IDIR/protobuf-c-$PBCVER/
PBINS=$IDIR/protobuf-$PBVER/
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$PBINS/lib:$PBCINS/lib

mkdir -p $SDIR
mkdir -p $IDIR

# clean up source dir first
rm -rf $SDIR/*

# remove this thing to force a rebuild of the citusdata extension, it might change quickly
rm $PINS/lib/cstore_fdw.so

# some setup for PostgreSQL according to Dr. Kyzirakos (TM)
# here: 16 GB
pg_shared_buffers=10GB
pg_effective_cache_size=6GB
pg_work_mem=5GB

#sudo bash -c "sysctl -w kernel.shmmax=11274289152"
#sudo bash -c "sysctl -w kernel.shmall=11274289152"
#sudo bash -c "sysctl -w kernel.shmmni=4096"

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
BMARK="tpch"

TIMINGCMD="/usr/bin/time -o $DIR/.time -f %e "
TIMEOUTCMD="timeout -k 35m 30m "

# http://mywiki.wooledge.org/BashFAQ/050
dropCache() {
	echo 3 | sudo /usr/bin/tee /proc/sys/vm/drop_caches
}

runQuery() { # runQuery PHASE REP DROPC
	for REP in {1..$2}
	do
		for QFILE in $QYDIR/q??.sql
		do
			if [ "$3" -gt 0 ] ; then
				dropCache
				# startup db
				eval "$SERVERCMD$DBFARM > /dev/null &"
				sleep 5
			fi

			q=${QFILE%.sql}
			qn=`basename $q`
			# run query
			eval "$TIMEOUTCMD$TIMINGCMD$CLIENTCMD$QFILE" > $QRDIR/$DB-SF$SF-coldrun$coldrun-$qn.out
			QTIME=`cat $DIR/.time`
			echo -e "$LOGPREFIX\t$1\t$qn\t$REP\t$QTIME" >> $RESFL

			if [ "$3" -gt 0 ] ; then
				# shutdown db
				shutdown
				sleep 5
			fi
			
		done
	done
}

for SF in $s
do
	# check if we have data
	SFDDIR=$DDIR/sf-$SF/
	# if not, generate
	if [ ! -f $SFDDIR/lineitem.tbl ] ; then
		# TPC-H dbgen installer
		if [ ! -f $IDIR/dbgen/dbgen ] ; then
			rm -rf $IDIR/dbgen/
			wget http://www.tpc.org/tpch/spec/tpch_2_16_1.zip -P $SDIR
			unzip $SDIR/tpch_*.zip -d $SDIR
			cd $SDIR/tpch_2_16_1/dbgen
			sed -e 's/DATABASE\s*=/DATABASE=DB2/' -e 's/MACHINE\s*=/MACHINE=LINUX/' -e 's/WORKLOAD\s*=/WORKLOAD=TPCH/' -e 's/CC\s*=/CC=gcc/' makefile.suite > Makefile
			make
			mkdir $IDIR/dbgen/
			cp dbgen dists.dss $IDIR/dbgen/
			rm -rf $SDIR/tpch_*
		fi
		if [ ! -f $IDIR/dbgen/dbgen ] ; then
			echo "Failed to install TPCH dbgen"
			exit -1
		fi

		cd $IDIR/dbgen/
		./dbgen -vf -s $SF
		mkdir -p $SFDDIR
		# clean up stupid line endings
		for i in *.tbl; do sed -i 's/.$//' $i ; done
		mv *.tbl $SFDDIR
	fi
	cd $DIR
	for DB in $d # postgres citusdata postgres monetdb
	do
		DBNAME=$DB-sf$SF
		DBFARM=$FARM/$DBNAME/
		#rm -rf $DBFARM/*

		if [ "$DB" == "monetdb" ]; then
			# MonetDB installer
			if [ ! -f $MINS/bin/mserver5 ] ; then
				rm -rf $MINS
				MURL=http://www.monetdb.org/downloads/sources/Latest/MonetDB-$MVER.tar.bz2
				wget $MURL -P $SDIR --no-check-certificate
				tar xvf $SDIR/MonetDB-*.tar.* -C $SDIR
				MSRC=$SDIR/MonetDB-$MVER/
				cd $MSRC
				./configure --prefix=$MINS --enable-rubygem=no --enable-python3=no --enable-python2=no --enable-perl=no --enable-geos=no --enable-python=no --enable-geom=no --enable-fits=no --enable-jaql=no --enable-gsl=no --enable-odbc=no --enable-jdbc=no --enable-merocontrol=no
				make -j install
				cd $DIR
				rm -rf $MSRC $SDIR/MonetDB-*.tar.*
			fi
			if [ ! -f $MINS/bin/mserver5 ] ; then
				echo "Failed to install MonetDB"
				exit -1
			fi

			SERVERCMD="$MINS/bin/mserver5 --set mapi_port=$PORT --daemon=yes --dbpath="
			CLIENTCMD="$MINS/bin/mclient -fcsv -p $PORT "
			INITFCMD="echo "
			CREATEDBCMD="echo createdb"
			shutdown() {
				kill $!
				sleep 10
				kill -9 $!
			}
			DBVER=$MVER
		fi

		if [ "$DB" == "postgres" ] || [ "$DB" == "citusdata" ]; then
			# PostgreSQL installer
			if [ ! -f $PINS/bin/postgres ] ; then
				rm -rf $PINS
				PGURL=http://ftp.postgresql.org/pub/source/v$PGVER/postgresql-$PGVER.tar.gz
				wget $PGURL -P $SDIR
				tar xvf $SDIR/postgresql-*.tar.* -C $SDIR
				PSRC=$SDIR/postgresql-$PGVER/
				cd $PSRC
				./configure --prefix=$PINS
				make
				make install
				cd $DIR
				rm -rf $PSRC $SDIR/postgresql-*.tar.*
			fi
			if [ ! -f $PINS/bin/postgres ] ; then
				echo "Failed to install PostgreSQL"
				exit -1
			fi

			# only preload citusdata lib if it exists
			PGPRELOAD=""
			if [ -f $PINS/lib/cstore_fdw.so ] ; then
				PGPRELOAD="-c shared_preload_libraries=cstore_fdw"
			fi
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
			$PGPRELOAD \
			 -D "
			CLIENTCMD="$PINS/bin/psql -p $PORT tpch -t -A -F , -f " 
			INITFCMD="$PINS/bin/initdb -D "
			CREATEDBCMD="$PINS/bin/createdb -p $PORT tpch"
			shutdown() {
				kill -INT $!
			}
			DBVER=$PGVER
		fi

		# TODO: does postgres run with a missing shared_preload?
		if [ "$DB" == "citusdata" ]; then
			# Citusdata installer
			if [ ! -f $PINS/lib/cstore_fdw.so ] ; then
				git clone https://github.com/citusdata/cstore_fdw/ $SDIR/cstore_fdw
				if [ ! -f $PBINS/bin/protoc ] || [ ! -f $PBCINS/bin/protoc-c ] ; then
					wget https://protobuf.googlecode.com/files/protobuf-$PBVER.tar.gz -P $SDIR
					wget https://protobuf-c.googlecode.com/files/protobuf-c-$PBCVER.tar.gz -P $SDIR
					tar xvf $SDIR/protobuf-$PBVER.tar.gz -C $SDIR
					tar xvf $SDIR/protobuf-c-$PBCVER.tar.gz -C $SDIR

					# protobuf and protbuf-c are dependencies of citusdb-store
					PBSRC=$SDIR/protobuf-$PBVER/
					cd $PBSRC
					./configure --prefix=$PBINS
					make -j install

					PBCSRC=$SDIR/protobuf-c-$PBCVER/
					cd $PBCSRC
					./configure --prefix=$PBCINS CXXFLAGS=-I$IDIR/protobuf-$PBVER/include LDFLAGS=-L$IDIR/protobuf-$PBVER/lib PATH=$PATH:$PBINS/bin/
					make -j install
				fi
				# cstore is a pgplugin
				CSRC=$SDIR/cstore_fdw
				cd $CSRC
				# some funny include path messing
				PATH=$PATH:$PINS/bin/:$PBCINS/bin/ CPATH=$CPATH:$PBCINS/include LIBRARY_PATH=$LIBRARY_PATH:$PBCINS/lib make -j install
				cd $DIR
				rm -rf $CSRC $PBCSRC $PBSRC $SDIR/protobuf-*.tar.*
			fi
			if [ ! -f $PINS/lib/cstore_fdw.so ] ; then
				echo "Failed to install CitusDB"
				exit -1
			fi
			DBVER=snapshot-`date +"%Y-%m-%d"`
		fi

		if [ "$DB" == "mariadb" ] ; then
			# MariaDB installer
			if [ ! -f $MAINS/bin/mysqld ] ; then
				rm -rf $MAINS
				MAURL=http://mariadb.mirror.triple-it.nl//mariadb-$MAVER/kvm-tarbake-jaunty-x86/mariadb-$MAVER.tar.gz
				wget $MAURL -P $SDIR
				tar xvf $SDIR/mariadb-*.tar.* -C $SDIR
				MASRC=$SDIR/mariadb-$MAVER/
				cd $MASRC
				cmake -DCMAKE_INSTALL_PREFIX:PATH=$MAINS .
				make
				make install
				cd $DIR
				rm -rf $MASRC $SDIR/mariadb-*.tar.*
			fi

			if [ ! -f $MAINS/bin/mysqld ] ; then
				echo "Failed to install MariaDB"
				exit -1
			fi

			DBSOCK=$DIR/.mariadb.socket
			SERVERCMD="$MAINS/bin/mysqld \
			--lower_case_table_names=1 \
			--basedir=$MAINS -P $PORT --pid-file=$DIR/.mariadb.pid --socket=$DBSOCK --datadir="
			CLIENTCMD="$MAINS/bin/mysql -u root --socket=$DBSOCK tpch < " 
			INITFCMD="$MAINS/scripts/mysql_install_db --basedir=$MAINS --datadir="
			CREATEDBCMD="$MAINS/bin/mysqladmin -u root --socket=$DBSOCK create tpch"
			shutdown() {
				$MAINS/bin/mysqladmin -u root --socket=$DBSOCK shutdown
			}
			DBVER=$MAVER
		fi

		LOGPREFIX="$DB\t$DBVER\t$BMARK\t$SF"
		if [ ! -d $DBFARM ] ; then
			# clear caches (fair loading)
			dropCache
			mkdir -p $DBFARM

			# initialize db directory
			eval "$INITFCMD$DBFARM"

			# start db server
			eval "$SERVERCMD$DBFARM > /dev/null &"
			sleep 5
			
			# create db (if applicable)
			eval "$CREATEDBCMD"
			
			# create schema
			sed -e "s|DIR|$DBFARM|" $SCDIR/$DB.schema.sql > $DIR/.$DB.schema.sql.local
			eval "$CLIENTCMD$DIR/.$DB.schema.sql.local" > /dev/null

			# load data
			sed -e "s|DIR|$SFDDIR|" $SCDIR/$DB.load.sql > $DIR/.$DB.load.sql.local
			eval "$TIMINGCMD$CLIENTCMD$DIR/.$DB.load.sql.local" > /dev/null
			LDTIME=`cat $DIR/.time`
			echo -e "$LOGPREFIX\tload\t\t\t$LDTIME" >> $RESFL

			# constraints
			eval "$TIMINGCMD$CLIENTCMD$SCDIR/$DB.constraints.sql" > /dev/null
			CTTIME=`cat $DIR/.time`
			echo -e "$LOGPREFIX\tconstraints\t\t\t$CTTIME" >> $RESFL

			# analyze/vacuum
			eval "$TIMINGCMD$CLIENTCMD$SCDIR/$DB.analyze.sql" > /dev/null
			AZTIME=`cat $DIR/.time`
			echo -e "$LOGPREFIX\tanalyze\t\t\t$AZTIME" >> $RESFL
			
			shutdown
		fi

		runQuery "coldruns" 5 1
		
		eval "$SERVERCMD$DBFARM > /dev/null &"
		sleep 5

		runQuery "warmup" 2 0
		runQuery "hotruns" 5 0
	
		shutdown
		sleep 5
	done
done

rm $DIR/.*.sql.local
rm $DIR/.time
rm -rf $SDIR/*



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
