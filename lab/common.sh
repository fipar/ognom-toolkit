msg()
{
    echo $*>&2
}

init_dbpath()
{
    [ $# -eq 1 ] || {
	cat <<EOF>&2
    usage: init_dbpath <directory>
    Initializes (creates if needed, removes data if any exists) a directory for use as an argument to --dbpath.
EOF
    }
    test -d $1 || mkdir -p $1
    rm -rf $1/*
    touch $1/mongod.pid
    chmod a+w $1/mongod.pid
}

start_mongod()
{
    [ -z "$MONGOD" ] && MONGOD=mongod
    [ $# -ge 2 ] || {
	cat <<EOF>&2
    usage: start_mongod <dbpath> <port> [replSet|configsvr]
    Starts a new mongod instance with the provided args for --dbpath and --port (and optionally indicates a replica set name, or starts the instance as a config server). 
    Initializes the datadir if needed. 
    If the environment variable MONGODB_ENGINE is defined, it is provided as arg for --storageEngine
EOF
    }
    dbpath=$1; port=$2; replSet=$3; storageEngine=""
    [ -n "$replSet" ] && {
	[ "$replSet" == "configsvr" ] && replSet="--configsvr" || replSet="--replSet $replSet"
    }
    [ -n "$MONGODB_ENGINE" ] && storageEngine="--storageEngine $MONGODB_ENGINE"
    $MONGOD --rest --httpinterface --dbpath $dbpath --port $port --logpath $dbpath/mongod.log $replSet --pidfilepath $dbpath/mongod.pid $storageEngine --fork
}

start_mongos()
{
    [ -z "$MONGOS" ] && MONGOS=mongos
    [ $# -eq 3 ] || {
	cat <<EOF>&2
    usage: start_mongos <dpath> <port> <configdb>
    Starts a new mongos instance with the specified arguments. 
EOF
    }
    dbpath=$1; port=$2; configdb=$3
    # we intentionally use mongod.pid below so we can use stop_mongo
    $MONGOS --setParameter enableTestCommands=1 --configdb $configdb --logpath $dbpath/mongos.log --port $port --pidfilepath $dbpath/mongod.pid --fork
}

stop_mongo()
{
    [ $# -eq 1 ] || {
cat <<EOF>&2
    usage: stop_mongo <dbpath>
    Sends SIGTERM to the mongod/mongos instance running out of the specified datadir. 
EOF
    }
    kill $(cat $1/mongod.pid)
}

identify_primary()
{
    cnt=0
    max_cnt=60
    port_prefix=2700
    port_suffix=1
    [ -n "$1" ] && port_suffix=$1
    primary_port=$(mongo --port ${port_prefix}${port_suffix} --eval "printjson(rs.status())"|grep --before-context 3 PRIMARY|head -1|awk -F: '{print $3}'|tr -d '",')
    while [ -z "$primary_port" -o $(echo $primary_port|grep -c 2700) -eq 0 ]; do
	sleep 1
	port_suffix=$((port_suffix+1))
	[ $port_suffix -ge 5 ] && port_suffix=1
	cnt=$((cnt+1))
	[ $cnt -ge $max_cnt ] && echo "Could not identify PRIMARY in less than $max_cnt seconds">&2 && return 1
	primary_port=$(mongo --port ${port_prefix}${port_suffix} --eval "printjson(rs.status())"|grep --before-context 3 PRIMARY|head -1|awk -F: '{print $3}'|tr -d '",')
    done
    echo $primary_port
}

wait_for_at_least_one_secondary()
{
    cnt=0
    max_cnt=60
    secondary_count=$(mongo --port $1 --eval "rs.status()"|grep -c SECONDARY)
    while [ $secondary_count -eq 0 ]; do
	sleep 1
	[ $cnt -ge $max_cnt ] && echo "Could not identify a SECONDARY in less than $max_cnt seconds">&2 && return 1
	secondary_count=$(mongo --port $1 --eval "printjson(rs.status())"|grep -c SECONDARY)
    done
}
