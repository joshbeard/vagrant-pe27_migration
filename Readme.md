# Vagrant Environment for PE 2.7 to 3.3 Migration

## Overview

This Vagrant environment is intended to be used for performing a Puppet
Enterprise 2.7.x migration to 3.3.x.

The scenario this demonstrates is that there's an existing 2.7 master in
production and our goal is to implement a new 3.3 master.  We make use of a
temporary master to do the database migration steps to obtain databases that
we can then import into our new 3.3 master.

PE 2.7 used MySQL for the PE console databases and 3.3 uses PostgreSQL. There
isn't a direct upgrade for 2.7 to 3.3.  The temporary master will start with
PE 2.7 and import the databases from the existing 2.7 master.  The temporary
system will be upgraded to 2.8.2.  From 2.8.2, it will be upgraded to 3.3, thus
migrating the databases that we can use on our new, permanent master.

The new 3.3 master should have the same `certname` as the in-place 2.7 master
that's being migrated to.  This is to provide a seamless transition for any
agents currently using the 2.7 master. Without this, all SSL certificates
would have to be re-generated and re-signed.

You could, technically, upgrade the same box in incremental versions, but that's
usually undesirable and generally preferable to start with a clean system.

For migrating from PE 2.8.x, the same guide can be used - just cut out the
specific steps for upgrading the 2.7 instance to 2.8

A corresponding guide for this procedure is available at [https://docs.google.com/document/d/1UlIxWLRT9_bbO0cK93xGPJYFbTGx_3rifFimIxWPb9g/edit?usp=sharing](https://docs.google.com/document/d/1UlIxWLRT9_bbO0cK93xGPJYFbTGx_3rifFimIxWPb9g/edit?usp=sharing)

An graphical overview of this procedure:

[https://raw.githubusercontent.com/joshbeard/vagrant-pe27_migration/master/docs/overview.jpg](https://raw.githubusercontent.com/joshbeard/vagrant-pe27_migration/master/docs/overview.jpg)

![overview](https://raw.githubusercontent.com/joshbeard/vagrant-pe27_migration/master/docs/overview.jpg)

**Four instances are provided:**

| System     | Address   | Description                                                                                                     |
| ---------- | --------- | --------------------------------------------------------------------------------------------------------------- |
| master27   | 10.0.4.60 | A PE 2.7.2 master, simulating an existing 2.7 master in production. This system will not be upgraded.           |
| tempmaster | 10.0.4.61 | This master gets 2.7.2 installed and is intended to be used to perform the database migration steps. It will go from 2.7.2 to 2.8.7 to 3.3.1. Once at 3.3.1, the console databases will be exported for use on the new, permanent 3.3.1 master |
| master33   | 10.0.4.62 | A 3.3 master representing a new, permanent 3.3 master that we'll be migrating to. It's a fresh install of 3.3.1. |
| agent      | 10.0.4.63 | An agent, installed with 2.7 at first and intended to be upgraded to 3.x                                        |

## Procedure

### 1. Bring up the systems

Start by bringing up each system and letting them provision:

```shell
vagrant up
```

Refer to the table above for the purpose of each system.

### 2. Perform Database Migration

#### Summary

A script to handle the database import/export is availble in `xfer/db.sh`

Your work will begin on the `master27` host, which represents an existing 2.7
master in production.  You'll export the console databases from that.

You'll then go to the `tempmaster` host, which has PE 2.7.2 installed.  You'll
import the databases from the previous step onto this system, then upgrade PE
to version 2.8.7.  After upgrading to 2.8.7, you'll upgrade it to 3.3.1.

Finally, once the temporary master has been fully upgraded and tested to ensure
the data migrated okay, you'll export the console databases from it and import
them into the new, permanent 3.3.1 `master33` box.

The 3.3.1 master gets installed with 3.3.1 and doesn't follow any PE upgrades.
We start with a clean box and simply bring the console databases and the SSL
certs over.

Once the master is stood up and current, agents can be upgraded to 3.3.

#### 2.1 Export original 2.7 master's databases

**On `master27`**

Once installed, add an example user via the PE console
([https://10.0.4.60](https://10.0.4.60)) and maybe a bogus class.  This is to
have some user-provided data that we can verify makes its way through the
database migrations.

Export the databases.  In this Vagrant environment, the script for this is at
`/vagrant/xfer/db.sh`:

```shell
/vagrant/xfer/db.sh export
```

This should dump three databases to the current working directory.
To make sharing easier, you might run this from the `/vagrant` directory.

***

#### 2.2 Import the original databases into the temporary master

**On `tempmaster`**

Import the databases from the `master27` box:

```shell
/vagrant/xfer/db.sh import
```

This will expect to find the SQL files for import in the current working
directory.  You might run this from the `/vagrant/xfer` path.

It's also a good idea to prune orphaned reports from the imported data. This
really isn't needed for this Vagrant demo, but would be in the "real world."

```shell
/opt/puppet/bin/rake -f /opt/puppet/share/puppet-dashboard/Rakefile \
  RAILS_ENV=production reports:prune:orphaned
```

Once imported, login to the console and do a quick check to see if the data
looks okay (ensure your sample user is there, your bogus class).
([https://10.0.4.61](https://10.0.4.61))

#### 2.3 Upgrade the temporary master to 2.8.7

**On `tempmaster`**

```shell
/vagrant/puppet/pe/puppet-enterprise-2.8.7-el-6-x86_64/puppet-enterprise-upgrader -A /vagrant/puppet/answers/master27.txt
```

Once upgraded, you might check the console to ensure it functions correctly.

#### 2.4 Upgrade `tempmaster` to Puppet Enterprise 3.3.1


**On `tempmaster`**

```shell
/vagrant/puppet/pe/puppet-enterprise-3.3.1-el-6-x86_64/puppet-enterprise-installer -A /vagrant/puppet/answers/master27.txt
```
Once upgraded, you might check the console to ensure it functions correctly and
that your sample user and class are there.

#### 2.5 Export the temporary master's databases

**On `tempmaster`**

After the temporary master is upgraded to 3.3.1, you're ready to export the
databases.

```shell
/vagrant/xfer/db.sh export
```

***

#### 2.6 Import the databases to the new 3.3 master

**On `master33`**

Now we're ready to prime our new, permanent 3.3 master with the databases.
PE 3.3 is already installed on this master (it was a clean install - not an
upgrade).

```shell
/vagrant/xfer/db.sh import
```

### 3. SSL Migration

#### Summary

There's basically two different scenarios to consider here:

1. The 2.7 master certname matches the new 3.3 master certname.  Essentially,
just swapping the masters out.
2. The certnames will differ between the existing 2.7 master and the new 3.3
master.  Having both active, for instance, and re-pointing agents.

The first scenario is easy - just use the same certnames when installing the
master.  As long as the new master has the original master's certname or has it
in its `dns_alt_names`, agents should be okay.  The ssl directory will transfer
without any fuss.

The second scenario is a little trickier.  There's a few things to consider -
what hostname are agents pointing to, and can you easily re-point agents to the
new master selectively?  To avoid having to regenerate certificates, the new
master will need the original master's certname in its list of `dns_alt_names`.

#### 3.1 Transfer SSL directory

The SSL directory from the existing master will need to be transfered to the
new master, preserving ownership and permissions.

On the Vagrant VM, use the `/vagrant/xfer` directory to share between nodes.  In the
real world, use other means, such as scp or rsync.  Just make sure ownership
gets preserved.

**On `master27`**

```shell
cd /etc/puppetlabs/puppet
tar czvf /vagrant/xfer/ssl.tar.gz ssl
```

**On `master33`**

Stop PE services first:

```shell
for s in httpd puppet puppetdb mcollective activemq memcached ; do
  service pe-$s stop
done
```

Backup the original SSL directory and extract the transferred one:

```shell
mv /etc/puppetlabs/puppet/ssl /etc/puppetlabs/puppet/orig.ssl
tar xzvf /vagrant/xfer/ssl.tar.gz -C /etc/puppetlabs/puppet
```

#### 3.2 Re-generate certificates

**If your new master has a different certificate name than your original PE 2.7
master, do this on the new 3.3 master: (This Vagrant demo fits this scenario)
If they are the same, this step is uneccesary**

```shell
/opt/puppet/bin/puppet cert generate master33.vagrant.vm --dns_alt_names=master27,master27.vagrant.vm,puppet,puppet.vagrant.vm
```

**Re-start pe-httpd and pe-memcached:**

```shell
service pe-httpd start
service pe-memcached start
```

**Re-generate the PuppetDB certificates:**

```shell
/opt/puppet/sbin/puppetdb ssl-setup -f
```

**Re-start the PuppetDB service:**

```shell
service pe-puppetdb start
```

**Re-generate the Console certificates:**

```shell
/opt/puppet/bin/puppet cert clean pe-internal-dashboard
rm -f /opt/puppet/share/puppet-dashboard/certs/*
cd /opt/puppet/share/puppet-dashboard

## Create new keys
/opt/puppet/bin/rake -f /opt/puppet/share/puppet-dashboard/Rakefile \
  RAILS_ENV=production cert:create_key_pair

## Submit a signing request
/opt/puppet/bin/rake -f /opt/puppet/share/puppet-dashboard/Rakefile \
  RAILS_ENV=production cert:request

## Sign the certificate
/opt/puppet/bin/puppet cert sign pe-internal-dashboard

## Retrieve the signed certs for the dashboard
/opt/puppet/bin/rake -f /opt/puppet/share/puppet-dashboard/Rakefile \
  RAILS_ENV=production cert:retrieve
```

**Generate certificates for peadmin (mcollective):**

This assumes you weren't previously using Mcollective on 2.7.

```shell
/opt/puppet/bin/puppet cert generate peadmin
```

**Restart services:**

```shell
for s in httpd puppet puppetdb mcollective activemq memcached ; do
  service pe-$s restart
done
```

### 4. Test

Hopefully that all went without too much of a hitch.  You should be able to
run agents against the new 3.3 master now, including itself.

**NOTE:** Give PuppetDB a minute to startup.

**On `agent`**

```shell
/opt/puppet/bin/puppet agent -t --server master33.vagrant.vm
```

You'll likely get a warning about mcollective on the agent.  That's okay.

Try to run the new PE 3.3 master agent:

**On `master33`**

```shell
/opt/puppet/bin/puppet agent -t
```

Login to the new 3.3 master's console ([https://10.0.4.61](https://10.0.4.61))
and verify things look right - your example user, your bogus class, and other
things.

### 5. Upgrade Agents

You can do this in several ways.

1. You can simply use the full 3.3 installer at `/vagrant/puppet/pe/`
2. Use the simplified PE installer (see [https://docs.puppetlabs.com/pe/latest/install_agents.html](https://docs.puppetlabs.com/pe/latest/install_agents.html))
3. Other custom ways (maybe a module)

To use the "simplified installer" (aka frictionless installer):

```shell
curl -k https://master33.vagrant.vm:8140/packages/current/install.bash | sudo bash
```

You'll have to change `master27` to `master33` in
`/etc/puppetlabs/puppet/puppet.conf`

You could create a Puppet module to do all this for you, so when agents run
against the old 2.7 master, they get everything they need to switch over.

## Acknowledgement

[Tom Linkin](https://github.com/trlinkin) provided the methods and guide for
performing the migration steps. This is his work in a Vagrantized fashion.

This makes use of Greg Sarjeant's [data-driven-vagrantfile](https://github.com/gsarjeant/data-driven-vagrantfile)

## Contributing

Contributions are very welcome.

Future revisions, if valuable, might include instructions for a split-install.
