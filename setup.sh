#!/bin/bash
set -x

# postgres user password (need to set this in the Dockerfile also)
export PGPASSWORD="abcdefg123456789"

# copy the pgpool template
cp files/pgpool.conf.template pgpool.conf

# setup the master postgresql server
MASTER_CID=`docker run -p 5432:5432 --name postgresql-master -itd --restart always --env 'DB_USER=dbuser' --env 'DB_PASS=dbuserpass' --env 'DB_NAME=dbname' --env 'REPLICATION_USER=repluser' --env 'REPLICATION_PASS=repluserpass' sameersbn/postgresql:9.4-21`
MASTER_IP=`docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${MASTER_CID}`

cat <<EOF >> pgpool.conf
backend_hostname0 = '${MASTER_IP}'
backend_port0 = 5432
backend_weight0 = 1
backend_flag0 = 'ALLOW_TO_FAILOVER'
EOF

SLAVE_COUNT=2

# now lets add some postgresql slaves
for i in $(seq 1 $SLAVE_COUNT)
do
	SLAVE_CID[$i]=`docker run --name postgresql-slave${i} -itd --restart always --link postgresql-master:master --env 'REPLICATION_MODE=slave' --env 'REPLICATION_SSLMODE=prefer' --env 'REPLICATION_HOST=master' --env 'REPLICATION_PORT=5432' --env 'REPLICATION_USER=repluser' --env 'REPLICATION_PASS=repluserpass' sameersbn/postgresql:9.4-21`
	SLAVE_IP[$i]=`docker inspect --format '{{ .NetworkSettings.IPAddress }}' ${SLAVE_CID[$i]}`

	cat <<EOF >> pgpool.conf
backend_hostname${i} = '${SLAVE_IP[$i]}'
backend_port${i} = 5432
backend_weight${i} = 1
backend_flag${i} = 'ALLOW_TO_FAILOVER'
EOF
done

sleep 10;

# verify postgresql replication
docker exec postgresql-master sudo -u postgres psql -c 'select client_addr, state, sent_location, write_location, flush_location, replay_location from pg_stat_replication'

# set the postgres password (has to be a better way to do this?)
docker exec postgresql-master sudo -u postgres psql -c "ALTER USER postgres WITH ENCRYPTED PASSWORD '${PGPASSWORD}'"

# restart postgresql-master
docker restart postgresql-master

# configure the pgpool2 image
docker build -t bdwilliams/docker-pgpool2 .

# now start the pgpool2 container
docker run -d --name docker-pgpool2 --restart always -p 9999:9999 bdwilliams/docker-pgpool2

sleep 10;

# create a test db
createdb -h 0.0.0.0 -p 9999 -U postgres testdb

# run a bench test
pgbench -i -s 10 -h 0.0.0.0 -p 9999 -U postgres testdb

# 
# for port in 5432 9999; do
# 	echo $port
# 	psql -c "SELECT min(aid), max(aid) FROM accounts" -p $port bench_parallel
# done
