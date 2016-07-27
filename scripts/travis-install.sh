#!/bin/bash -eux

sudo wget "http://archive.cloudera.com/$CDH/ubuntu/precise/amd64/cdh/cloudera.list" \
    -O /etc/apt/sources.list.d/cloudera.list
# work around broken list
sudo sed -i 's mirror.infra.cloudera.com/archive archive.cloudera.com g' \
    /etc/apt/sources.list.d/cloudera.list
sudo apt-get update

#
# Kerberos
#

wget http://web.mit.edu/kerberos/dist/krb5/1.14/krb5-1.14.3.tar.gz
tar -xvzf krb5-1.14.3.tar.gz
cd krb5-1.14.3/src
./configure && make
make install
sudo cp $(dirname $0)/travis-conf/kerberos-config/krb5.conf /etc/krb5.conf
sudo cp $(dirname $0)/travis-conf/kerberos-config/kdc.conf /usr/local/var/krb5kdc/kdc.conf
sudo apt-get install expect
expect -c '
  proc abort {} {
    exit 1
  }
  spawn sudo /usr/local/sbin/kdb5_util create -s 
  expect {
    -ex {Enter KDC database master key: }          { send "realmpwd\n"; exp_continue }
    -ex {Re-enter KDC database master key to verify: }          { send "realmpwd\n"; exp_continue }
    default          abort
  }
'


#
# LDAP
#
sudo -E apt-get -yq --no-install-suggests --no-install-recommends --force-yes install ldap-utils slapd
sudo mkdir /tmp/slapd
sudo slapd -f $(dirname $0)/ldap_config/slapd.conf -h ldap://localhost:3389 &
sleep 10
sudo ldapadd -h localhost:3389 -D cn=admin,dc=example,dc=com -w test -f $(dirname $0)/../pyhive/tests/ldif_data/base.ldif
sudo ldapadd -h localhost:3389 -D cn=admin,dc=example,dc=com -w test -f $(dirname $0)/../pyhive/tests/ldif_data/INITIAL_TESTDATA.ldif

#
# Hive
#

sudo apt-get install -y --force-yes hive
sudo cp $(dirname $0)/travis-conf/hive/hive-site.xml /etc/hive/conf/hive-site.xml
sudo -u hive mkdir /tmp/hive && sudo chmod 777 /tmp/hive
sudo apt-get install -y --force-yes hive-metastore hive-server2

sudo -Eu hive $(dirname $0)/make_test_tables.sh

#
# Presto
#

sudo apt-get install -y python # Use python2 for presto server
sudo apt-get install -y oracle-java8-installer
sudo update-java-alternatives -s java-8-oracle

curl https://repo1.maven.org/maven2/com/facebook/presto/presto-server/$PRESTO/presto-server-$PRESTO.tar.gz \
    | tar zxf -

cp -r $(dirname $0)/travis-conf/presto presto-server-$PRESTO/etc
sed -i s/%CDH%/$CDH/g presto-server-$PRESTO/etc/catalog/hive.properties

if [ "$PRESTO" == "0.97" ]
then
    sed -i '/query.max-memory/d' presto-server-$PRESTO/etc/config.properties
fi

/usr/bin/python2.7 presto-server-$PRESTO/bin/launcher.py start
