FROM ubuntu:trusty

RUN apt-get update && apt-get install pgpool2 postgresql-client-9.3 vim -y

COPY pgpool.conf /etc/pgpool2/
COPY files/pool_hba.conf /etc/pgpool2/

RUN pg_md5 -f /etc/pgpool2/pgpool.conf -m -u postgres abcdefg123456789

EXPOSE 9999

CMD pgpool -n