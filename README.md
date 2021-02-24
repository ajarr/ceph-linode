# Repository of scripts to deploy Ceph in Linode

The repository has a collection of scripts that automate the deployment of Ceph
within Linode. The primary use-case for this work is to allow rapid testing of
Ceph at scale.

## Why Linode?

Linode is a popular virtual private server (VPS) provider, but one of several. The primary reasons for selecting Linode were

* **Price.** Linode is generally very affordable compared to competition.

* **SSD local storage at no extra cost.** Obviously, testing Ceph requires the use of OSDs that require local devices. The SSDs on Linode are enterprise quality and well provisioned.

* **Friendly API.** Most cloud providers have an API today for deployment. At the time I first worked on this project, there were not many that did.

Want to add another cloud provider? I'm all-ears. Please talk to me by email
(see commit history for email address).

## Repository Organization

The repository has a number of utilities roughly organized as:

* `linode.py`: script to rapidly create/configure/nuke/destroy Linodes.

* `cluster.json`: the description of the cluster to deploy.

* `pre-config.yml`: an ansible playbook to pre-configure Linodes with useful
   packages or utilities prior to installing Ceph.

* `cephadm.yml`: an ansible playbook to install Ceph using cephadm.

* `playbooks/`: ansible playbooks for running serial tests and collecting test
  artifacts and performance data. Note that most of these playbooks were
  written for testing CephFS.

* `scripts/` and `misc/`: miscellaneous scripts. Notably, workflow management
  scripts for testing CephFS are located here.

* `graphing/`: graphing scripts using gnuplot and some ImageMagik utilities.
  These may run on the artifacts produced by the ansible playbooks in
  `playbooks`.


## How-to Get Started:

> :fire: **Note** :fire: For non-toy deployments, it's recommended to use a
> dedicated linode for running ansible. This reduces latency of
> operations, internet hiccups, allows you to allocate enough RAM for
> memory-hungry ansible, and rapidly download test artifacts for archival.
> Generally, the more RAM/cores the better. **Also**: make sure to [enable a
> private IP
> address](https://www.linode.com/docs/platform/manager/remote-access/#adding-private-ip-addresses)
> on the ansible linode otherwise ansible will not be able to communicate with
> the ceph cluster.

* Setup a Linode account and [get an API key](https://www.linode.com/docs/platform/api/api-key).

  Put the key in `~/.linode.key`:

  ```bash
  cat > ~/.linode.key
  ABCFejfASFG...
  ^D
  ```

* Setup an ssh key if not already done:

  ```bash
  ssh-keygen
  ```

* Install necessary packages:

  **CentOS Stream**:

    ```bash
    dnf install epel-release
    dnf update
    dnf install git ansible python3-pip python3-netaddr jq rsync wget htop
    pip3 install linode_api4 notario
    ```

  **Fedora**:

    ```bash
    dnf install git ansible python3-notario python3-pip python3-netaddr jq rsync htop wget
    pip3 install linode_api4
    ```

  **Arch Linux**:

    ```bash
    pacman -Syu git ansible python3-netaddr python3-pip jq rsync htop wget
    pip3 install notario linode_api4
    ```

* Clone ceph-linode:

  ```bash
  git clone https://github.com/batrick/ceph-linode.git
  ```

* Copy `cluster.json.sample` to `cluster.json` and modify it to have the
  desired count and Linode plan for each daemon type. If you're planning to do
  testing with CephFS, it is recommend to have 3+ MDS, 2+ clients, and 8+ OSDs.
  The ansible playbook `playbooks/cephfs-setup.yml` will configure 4 OSDs to be
  dedicated for the metadata pool. Keep in mind that the use of containerized
  Ceph daemons requires more memory than bare-metal installations. It is
  recommended to use at least 4GB for all daemons. OSDs require at least 8GB.

> :fire: **Note** :fire: The OSD memory target is always at least 4GB, otherwise set appropriately and automatically based on the available memory on the OSD. If you use smaller OSDs (4GB or smaller), then you must configure the memory target manually via changing the Ceph config.

* Start using:

    ```bash
    python3 linode.py launch
    source ansible-env.sh
    do_playbook cephadm.yml
    ```

## SSH to a particular machine

```bash
./ansible-ssh mon-000
```

Or any named node in the `linodes` JSON file.

## Execute ansible commands against the cluster

```bash
source ansible-env.bash
ans -m shell -a 'echo im an osd' osds
ans -m shell -a 'echo im an mds' mdss
ans -m shell -a 'echo im a client' clients
...
```

You can also easily execute playbooks:

```bash
source ansible-env.bash
do_playbook foo.yml
```

## How-to nuke and repave your cluster:

Sometimes you want to start over from a clean slate. Destroying the cluster can
incur unnecessary costs though as Linodes are billed by the hour, no matter how
little of an hour you use. It is often cheaper to *nuke* the Linodes by
deleting all configurations, destroying all disks, etc.

You can manually nuke the cluster if you want using:

```bash
python3 linode.py nuke
```

## How-to destroy your cluster:

```bash
python3 linode.py destroy
```

The script works by destroying all the Linodes that belong to the group named
in the `LINODE_GROUP` file, created by `linode.py`.

This deletes EVERYTHING and stops any further billing.
